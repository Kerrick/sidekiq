# frozen_string_literal: true

# https://www.rooibos.run
gem 'rooibos', '>= 0.7.0'
require 'rooibos'

RatatuiRuby.debug_mode!

require 'sidekiq/api'
require 'sidekiq/paginator'

require 'logger'
Sidekiq.default_configuration.logger = Logger.new(IO::NULL)

require_relative 'tui/tabs'
require_relative 'tui/data'
require_relative 'tui/views'
require_relative 'tui/messages'
require_relative 'tui/commands'
require_relative 'tui/fragments/table_fragment'
require_relative 'tui/tabs/home_tab'
require_relative 'tui/tabs/busy_tab'
require_relative 'tui/tabs/queues_tab'
require_relative 'tui/fragments/set_fragment'
require_relative 'tui/tabs/scheduled_tab'
require_relative 'tui/tabs/retries_tab'
require_relative 'tui/tabs/dead_tab'
require_relative 'tui/tabs/metrics_tab'

DebugLogger = Logger.new('tui.log')
def log(*x)
  x.each { |item| DebugLogger.info { item } }
end

module Sidekiq
  module TUI
    include Rooibos::Router

    REFRESH_INTERVAL = 2.0

    TAB_MODULES = {
      home: HomeTab, busy: BusyTab, queues: QueuesTab, scheduled: ScheduledTab,
      retries: RetriesTab, dead: DeadTab, metrics: MetricsTab
    }.freeze

    Model = Data.define(
      :active_tab, :showing, :stats, :redis_url, :error,
      :home, :busy, :queues, :scheduled, :retries, :dead, :metrics
    )

    Init = lambda {
      model = Ractor.make_shareable Model.new(
        active_tab: :home, showing: :main,
        stats: EMPTY_STATS, redis_url: 'N/A', error: nil,
        home: HomeTab::Init[],
        busy: BusyTab::Init[],
        queues: QueuesTab::Init[],
        scheduled: ScheduledTab::Init[],
        retries: RetriesTab::Init[],
        dead: DeadTab::Init[],
        metrics: MetricsTab::Init[]
      )
      [model,
       Rooibos::Command.batch(FetchStats.new, FetchRedisInfo.new, Rooibos::Command.tick(REFRESH_INTERVAL, :refresh))]
    }

    View = lambda { |model, tui|
      model.showing == :help ? RenderHelp[model, tui] : RenderMain[model, tui]
    }

    # --- Fragment routes ---

    route :home, to: HomeTab
    route :busy, to: BusyTab
    route :queues, to: QueuesTab
    route :scheduled, to: ScheduledTab
    route :retries, to: RetriesTab
    route :dead, to: DeadTab
    route :metrics, to: MetricsTab

    # --- Help overlay (modal — swallows all events) ---

    only when: ->(_, model) { model.showing == :help } do
      receive_events %i[esc ?], ->(_, model) { model.with(showing: :main) }
      receive_instances_of RatatuiRuby::Event, ->(_, _) { nil }
    end

    # --- Global keys ---

    action :quit, -> { Rooibos::Command.exit }
    receive_events %i[q ctrl_c], :quit
    receive_events :"?", ->(_, model) { model.with(showing: :help) }

    receive_events :left, lambda { |_, model|
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx - 1) % TAB_ORDER.size]
      [model.with(active_tab: new_tab, error: nil, new_tab => TAB_MODULES[new_tab]::Init[]),
       FetchCommandFor[model, new_tab]]
    }

    receive_events :right, lambda { |_, model|
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx + 1) % TAB_ORDER.size]
      [model.with(active_tab: new_tab, error: nil, new_tab => TAB_MODULES[new_tab]::Init[]),
       FetchCommandFor[model, new_tab]]
    }

    # --- Timer ---

    receive_routed :refresh, lambda { |_, model|
      [model, Rooibos::Command.batch(
        FetchCommandFor[model, model.active_tab],
        Rooibos::Command.tick(REFRESH_INTERVAL, :refresh)
      )]
    }

    # --- Data fetch results ---

    observe_instances_of StatsFetched, lambda { |message, model|
      model.with(stats: message.stats, redis_url: message.redis_url, error: nil)
    }

    forward_instances_of StatsFetched, to: :home
    forward_instances_of RedisInfoFetched, to: :home
    forward_instances_of ProcessesFetched, to: :busy
    forward_instances_of QueuesFetched, to: :queues
    forward_instances_of ScheduledFetched, to: :scheduled
    forward_instances_of RetriesFetched, to: :retries
    forward_instances_of DeadFetched, to: :dead
    forward_instances_of MetricsFetched, to: :metrics

    receive_instances_of DataFetchError, lambda { |message, model|
      log("DataFetchError: #{message.error_message}", *Array(message.backtrace))
      model.with(error: message)
    }

    receive_instances_of ActionComplete, lambda { |_, model|
      DebugLogger.info("Root ActionComplete: re-fetching tab=#{model.active_tab}")
      [model, FetchCommandFor[model, model.active_tab]]
    }

    # --- Semantic key→message forwarding to active tab ---

    SHARED_TABLE_KEYS = { j: :row_down, k: :row_up, x: :toggle_select, shift_A: :toggle_select_all,
                          h: :prev_page, l: :next_page }.freeze
    SHARED_TABLE_DISPLAY = [['h/l', 'Prev/Next Page'], ['j/k', 'Prev/Next Row'],
                            ['x', 'Select'], ['A', 'Select All']].freeze

    # When a set tab is filtering, forward raw events so the
    # filtering modal can capture keystrokes.
    SET_TABS = %i[scheduled retries dead].freeze
    IsSetFiltering = lambda { |_, model|
      SET_TABS.include?(model.active_tab) && model.public_send(model.active_tab).set.filtering
    }

    only when: IsSetFiltering do
      otherwise route_to: :scheduled, when: ->(_, model) { model.active_tab == :scheduled }
      otherwise route_to: :retries,   when: ->(_, model) { model.active_tab == :retries }
      otherwise route_to: :dead,      when: ->(_, model) { model.active_tab == :dead }
    end

    only when: ->(_, model) { model.active_tab == :busy } do
      route_to :busy do
        SHARED_TABLE_KEYS.each { |key, semantic| forward_events key, as: semantic }
        BusyTab::Controls.each { |control| forward_events control.key, as: control.semantic }
      end
    end

    only when: ->(_, model) { model.active_tab == :queues } do
      route_to :queues do
        SHARED_TABLE_KEYS.each { |key, semantic| forward_events key, as: semantic }
        QueuesTab::Controls.each { |control| forward_events control.key, as: control.semantic }
      end
    end

    only when: ->(_, model) { model.active_tab == :scheduled && !model.scheduled.set.filtering } do
      route_to :scheduled do
        SHARED_TABLE_KEYS.each { |key, semantic| forward_events key, as: semantic }
        ScheduledTab::Controls.each { |control| forward_events control.key, as: control.semantic }
      end
    end

    only when: ->(_, model) { model.active_tab == :retries && !model.retries.set.filtering } do
      route_to :retries do
        SHARED_TABLE_KEYS.each { |key, semantic| forward_events key, as: semantic }
        RetriesTab::Controls.each { |control| forward_events control.key, as: control.semantic }
      end
    end

    only when: ->(_, model) { model.active_tab == :dead && !model.dead.set.filtering } do
      route_to :dead do
        SHARED_TABLE_KEYS.each { |key, semantic| forward_events key, as: semantic }
        DeadTab::Controls.each { |control| forward_events control.key, as: control.semantic }
      end
    end

    Update = from_router

    # --- Helper lambdas ---

    FetchCommandFor = lambda { |model, tab|
      tab_model = model.public_send(tab)
      tab_module = TAB_MODULES[tab]
      Rooibos::Command.batch(FetchStats.new, *tab_module::FetchCommand[tab_model])
    }

    ControlsForTab = lambda { |model|
      tab = model.active_tab
      tab_module = TAB_MODULES[tab]
      common = [['?', 'Help'], ['←/→', 'Select Tab'], ['q', 'Quit']]
      tab_controls = tab_module::Controls
      return common if tab_controls.empty?

      tab_display = tab_controls.map { |control| [control.display_key, control.description] }
      common + SHARED_TABLE_DISPLAY + tab_display
    }

    RenderMain = lambda { |model, tui|
      tab_bar = tui.tabs(
        titles: TAB_ORDER.map { |tab| TAB_NAMES[tab] },
        selected_index: TAB_ORDER.index(model.active_tab),
        block: tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Views::TITLE_STYLE),
        divider: ' | ', highlight_style: Views::HIGHLIGHT_STYLE
      )

      content = if model.error
                  Views::RenderError[model.error, tui]
                else
                  TAB_MODULES[model.active_tab]::View[model.public_send(model.active_tab), tui, stats: model.stats]
                end

      spans = ControlsForTab[model].flat_map do |key, desc|
        [tui.text_span(content: key, style: Views::HOTKEY_STYLE), tui.text_span(content: ": #{desc}  ")]
      end
      controls = tui.paragraph(
        text: [tui.text_line(spans: spans),
               tui.text_line(spans: [tui.text_span(content: "Redis: #{model.redis_url} "),
                                     tui.text_span(content: "Current Time: #{Time.now.utc}")])],
        block: tui.block(title: 'Controls', borders: [:all])
      )

      tui.layout(
        direction: :vertical,
        constraints: [tui.constraint_length(3), tui.constraint_fill(1), tui.constraint_length(4)],
        children: [tab_bar, content, controls]
      )
    }

    RenderHelp = lambda { |_, tui|
      help_lines = [["Esc", "Close"], ["←/→", "Move between tabs"],
                    ["j/k", "Use vim keys to move to prev/next row"], ["x", "Select/deselect current row"],
                    ["A", "Select/deselect All visible rows"], ["h/l", "Use vim keys to move to prev/next page"], ["q", "Quit"]]
      text_lines = [tui.text_line(spans: ['Welcome to the Sidekiq Terminal UI'], alignment: :center)] +
                   help_lines.map do |key, desc|
                     tui.text_line(spans: [tui.text_span(content: key, style: Views::HOTKEY_STYLE),
                                           tui.text_span(content: ": #{desc}")])
                   end
      content = tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Views::TITLE_STYLE,
                          children: [tui.paragraph(text: text_lines)])
      ctrl = tui.paragraph(
        text: [tui.text_line(spans: [tui.text_span(content: 'Esc', style: Views::HOTKEY_STYLE),
                                     tui.text_span(content: ': Close  ')])],
        block: tui.block(title: 'Controls', borders: [:all])
      )
      tui.layout(direction: :vertical,
                 constraints: [tui.constraint_fill(1), tui.constraint_length(4)],
                 children: [content, ctrl])
    }
  end
end
