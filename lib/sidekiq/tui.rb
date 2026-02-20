# frozen_string_literal: true

# https://www.rooibos.run
gem "rooibos", ">= 0.7.0"
require "rooibos"

RatatuiRuby.debug_mode!

require "sidekiq/api"
require "sidekiq/paginator"

require "logger"
Sidekiq.default_configuration.logger = Logger.new(IO::NULL)

require_relative "tui/tabs"
require_relative "tui/shared"
require_relative "tui/messages"
require_relative "tui/commands"
require_relative "tui/tabs/home_tab"
require_relative "tui/tabs/busy_tab"
require_relative "tui/tabs/queues_tab"
require_relative "tui/tabs/set_tab"
require_relative "tui/tabs/metrics_tab"

DebugLogger = Logger.new("tui.log")
def log(*x)
  x.each { |item| DebugLogger.info { item } }
end

module Sidekiq
  module TUI
    include Rooibos::Router

    REFRESH_INTERVAL = 2.0

    Model = Data.define(
      :active_tab, :showing, :stats, :redis_url, :error,
      :home, :busy, :queues, :scheduled, :retries, :dead, :metrics
    )

    Init = -> {
      model = Ractor.make_shareable Model.new(
        active_tab: :home, showing: :main,
        stats: EMPTY_STATS, redis_url: "N/A", error: nil,
        home: HomeTab::Init[],
        busy: BusyTab::Init[],
        queues: QueuesTab::Init[],
        scheduled: SetTab::Init[tab_name: :scheduled, set_class_name: "Sidekiq::ScheduledSet",
                                allowed_actions: %i[delete add_to_queue kill]],
        retries: SetTab::Init[tab_name: :retries, set_class_name: "Sidekiq::RetrySet",
                              allowed_actions: %i[delete retry kill]],
        dead: SetTab::Init[tab_name: :dead, set_class_name: "Sidekiq::DeadSet",
                           allowed_actions: %i[delete add_to_queue]],
        metrics: MetricsTab::Init[]
      )
      [model, Rooibos::Command.batch(FetchHome.new, Rooibos::Command.tick(REFRESH_INTERVAL, :refresh))]
    }

    View = ->(model, tui) {
      model.showing == :help ? RenderHelp[model, tui] : RenderMain[model, tui]
    }

    # --- Fragment routes ---

    route :home, to: HomeTab
    route :busy, to: BusyTab
    route :queues, to: QueuesTab
    route :scheduled, to: SetTab
    route :retries, to: SetTab
    route :dead, to: SetTab
    route :metrics, to: MetricsTab

    # --- Help overlay (modal — swallows all events) ---

    only when: ->(_, m) { m.showing == :help } do
      receive_events :esc, ->(_, model) { model.with(showing: :main) }
      receive_all ->(_, model) { model }
    end

    # --- Global keys ---

    action :quit, -> { Rooibos::Command.exit }
    receive_events %i[q ctrl_c], :quit
    receive_events :"?", ->(_, model) { model.with(showing: :help) }

    receive_events :left, ->(_, model) {
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx - 1) % TAB_ORDER.size]
      [model.with(active_tab: new_tab, error: nil), FetchCommandFor[model, new_tab]]
    }

    receive_events :right, ->(_, model) {
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx + 1) % TAB_ORDER.size]
      [model.with(active_tab: new_tab, error: nil), FetchCommandFor[model, new_tab]]
    }

    # --- Timer ---

    receive_routed :refresh, ->(_, model) {
      [model, Rooibos::Command.batch(
        FetchCommandFor[model, model.active_tab],
        Rooibos::Command.tick(REFRESH_INTERVAL, :refresh)
      )]
    }

    # --- Data fetch results ---

    observe_instances_of DataFetched, ->(msg, model) {
      model.with(stats: msg.stats, redis_url: msg.redis_url, error: nil)
    }

    forward_instances_of DataFetched, to: :home, when: ->(msg, _) { msg.tab == :home }
    forward_instances_of DataFetched, to: :busy, when: ->(msg, _) { msg.tab == :busy }
    forward_instances_of DataFetched, to: :queues, when: ->(msg, _) { msg.tab == :queues }
    forward_instances_of DataFetched, to: :scheduled, when: ->(msg, _) { msg.tab == :scheduled }
    forward_instances_of DataFetched, to: :retries, when: ->(msg, _) { msg.tab == :retries }
    forward_instances_of DataFetched, to: :dead, when: ->(msg, _) { msg.tab == :dead }
    forward_instances_of DataFetched, to: :metrics, when: ->(msg, _) { msg.tab == :metrics }

    receive_instances_of DataFetchError, ->(msg, model) {
      log("DataFetchError: #{msg.error_message}", *Array(msg.backtrace))
      model.with(error: msg.error_message)
    }

    receive_instances_of ActionComplete, ->(_, model) {
      [model, FetchCommandFor[model, model.active_tab]]
    }

    # --- Filtering modal: when active, forward raw events to the set tab ---
    # Must come BEFORE the semantic key forwards (first match wins).

    FILTERING = ->(_, m) { SET_TABS.include?(m.active_tab) && m.public_send(m.active_tab).filtering }

    only when: FILTERING do
      otherwise route_to: :scheduled, when: ->(_, m) { m.active_tab == :scheduled }
      otherwise route_to: :retries, when: ->(_, m) { m.active_tab == :retries }
      otherwise route_to: :dead, when: ->(_, m) { m.active_tab == :dead }
    end

    # --- Semantic key→message forwarding to active tab ---
    # Keybinding knowledge lives HERE ONLY. Tabs never see raw keys.

    SHARED_TABLE_KEYS = { j: :row_down, k: :row_up, x: :toggle_select, shift_A: :toggle_select_all,
                          h: :prev_page, l: :next_page }.freeze

    # Busy tab
    only when: ->(_, m) { m.active_tab == :busy } do
      route_to :busy do
        SHARED_TABLE_KEYS.each { |key, msg| forward_events key, as: msg }
        forward_events :shift_T, as: :terminate
        forward_events :shift_Q, as: :quiet
      end
    end

    # Queues tab
    only when: ->(_, m) { m.active_tab == :queues } do
      route_to :queues do
        SHARED_TABLE_KEYS.each { |key, msg| forward_events key, as: msg }
        forward_events :shift_D, as: :delete_queue
        forward_events :p, as: :toggle_pause
      end
    end

    # Set tabs (when NOT filtering — filtering modal handles raw events above)
    %i[scheduled retries dead].each do |tab|
      not_filtering = ->(_, m) { m.active_tab == tab && !m.public_send(tab).filtering }
      only when: not_filtering do
        route_to tab do
          SHARED_TABLE_KEYS.each { |key, msg| forward_events key, as: msg }
          forward_events :shift_D, as: :delete
          forward_events :shift_R, as: :retry
          forward_events :shift_E, as: :enqueue
          forward_events :shift_K, as: :kill
          forward_events :"/", as: :start_filter
        end
      end
    end

    Update = from_router

    # --- Helper lambdas ---

    FetchCommandFor = ->(model, tab) {
      case tab
      when :home then FetchHome.new
      when :busy then FetchBusy.new
      when :queues then FetchQueues.new
      when :scheduled, :retries, :dead
        set_model = model.public_send(tab)
        FetchSet.new(tab:, set_class_name: SET_CLASS_NAMES[tab],
                     filter: set_model.filter, pager_page: set_model.pager.page,
                     pager_size: set_model.pager.size)
      when :metrics then FetchMetrics.new
      end
    }

    ControlsForTab = ->(tab) {
      common = [["?", "Help"], ["←/→", "Select Tab"], ["q", "Quit"]]
      return common if tab == :home || tab == :metrics

      table_ctrls = [["h/l", "Prev/Next Page"], ["j/k", "Prev/Next Row"],
                     ["x", "Select"], ["A", "Select All"]]
      tab_ctrls = case tab
        when :busy then [["T", "Terminate"], ["Q", "Quiet"]]
        when :queues then [["D", "Delete"], ["p", "Pause/Unpause"]]
        when :scheduled then [["D", "Delete"], ["E", "Enqueue"], ["K", "Kill"], ["/", "Filter"]]
        when :retries then [["D", "Delete"], ["R", "Retry"], ["K", "Kill"], ["/", "Filter"]]
        when :dead then [["D", "Delete"], ["E", "Enqueue"], ["/", "Filter"]]
        else []
      end
      common + table_ctrls + tab_ctrls
    }

    TAB_MODULES = {
      home: HomeTab, busy: BusyTab, queues: QueuesTab, scheduled: SetTab,
      retries: SetTab, dead: SetTab, metrics: MetricsTab
    }.freeze

    RenderMain = ->(model, tui) {
      tab_bar = tui.tabs(
        titles: TAB_ORDER.map { |t| TAB_NAMES[t] },
        selected_index: TAB_ORDER.index(model.active_tab),
        block: tui.block(title: Sidekiq::NAME, borders: [:all], title_style: TITLE_STYLE),
        divider: " | ", highlight_style: HIGHLIGHT_STYLE
      )

      content = if model.error
        RenderError[model.error, tui]
      else
        TAB_MODULES[model.active_tab]::View[model.public_send(model.active_tab), tui, stats: model.stats]
      end

      spans = ControlsForTab[model.active_tab].flat_map { |key, desc|
        [tui.text_span(content: key, style: HOTKEY_STYLE), tui.text_span(content: ": #{desc}  ")]
      }
      controls = tui.paragraph(
        text: [tui.text_line(spans: spans),
               tui.text_line(spans: [tui.text_span(content: "Redis: #{model.redis_url} "),
                                     tui.text_span(content: "Current Time: #{Time.now.utc}")])],
        block: tui.block(title: "Controls", borders: [:all])
      )

      tui.layout(
        direction: :vertical,
        constraints: [tui.constraint_length(3), tui.constraint_fill(1), tui.constraint_length(4)],
        children: [tab_bar, content, controls]
      )
    }

    RenderHelp = ->(_model, tui) {
      help_lines = [["Esc", "Close"], ["←/→", "Move between tabs"],
                    ["j/k", "Prev/next row"], ["x", "Select/deselect current row"],
                    ["A", "Select/deselect All"], ["h/l", "Prev/next page"], ["q", "Quit"]]
      text_lines = [tui.text_line(spans: ["Welcome to the Sidekiq Terminal UI"], alignment: :center)] +
        help_lines.map { |key, desc|
          tui.text_line(spans: [tui.text_span(content: key, style: HOTKEY_STYLE),
                                tui.text_span(content: ": #{desc}")])
        }
      content = tui.block(title: Sidekiq::NAME, borders: [:all], title_style: TITLE_STYLE,
                          children: [tui.paragraph(text: text_lines)])
      ctrl = tui.paragraph(
        text: [tui.text_line(spans: [tui.text_span(content: "Esc", style: HOTKEY_STYLE),
                                     tui.text_span(content: ": Close  ")])],
        block: tui.block(title: "Controls", borders: [:all])
      )
      tui.layout(direction: :vertical,
                 constraints: [tui.constraint_fill(1), tui.constraint_length(4)],
                 children: [content, ctrl])
    }
  end
end
