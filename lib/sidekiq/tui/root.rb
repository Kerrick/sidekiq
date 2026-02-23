# frozen_string_literal: true

module Sidekiq
  module TUI
    include Rooibos::Router

    REFRESH_INTERVAL = 2.0

    TAB_ORDER = %i[home busy queues scheduled retries dead metrics].freeze
    TAB_NAMES = {
      home: 'Home', busy: 'Busy', queues: 'Queues', scheduled: 'Scheduled',
      retries: 'Retries', dead: 'Dead', metrics: 'Metrics'
    }.freeze
    SET_TABS = %i[scheduled retries dead].freeze

    TAB_MODULES = {
      home: Home, busy: Busy, queues: Queues, scheduled: Scheduled,
      retries: Retries, dead: Dead, metrics: Metrics
    }.freeze

    Model = Data.define(
      :active_tab, :showing, :stats, :stats_loading, :redis_url, :error,
      :home, :busy, :queues, :scheduled, :retries, :dead, :metrics
    )

    Init = lambda {
      tick = Rooibos::Command.tick(REFRESH_INTERVAL, :refresh)
      home_model, home_cmd = Home::Init[]
      model = Ractor.make_shareable Model.new(
        active_tab: :home, showing: :main,
        stats: Stats::Record::EMPTY, stats_loading: true, redis_url: 'N/A', error: nil,
        home: home_model,
        busy: Busy::Init[].first,
        queues: Queues::Init[].first,
        scheduled: Scheduled::Init[].first,
        retries: Retries::Init[].first,
        dead: Dead::Init[].first,
        metrics: Metrics::Init[].first
      )
      [model, Rooibos::Command.batch(Stats::Fetch.new, home_cmd, tick)]
    }

    View = lambda { |model, tui|
      model.showing == :help ? RenderHelp[model, tui] : RenderMain[model, tui]
    }

    # --- Fragment routes ---

    route :home, to: Home
    route :busy, to: Busy
    route :queues, to: Queues
    route :scheduled, to: Scheduled
    route :retries, to: Retries
    route :dead, to: Dead
    route :metrics, to: Metrics

    # --- Help overlay (modal — swallows all events) ---

    only when: ->(_, model) { model.showing == :help } do
      receive_events %i[esc ?], ->(_, model) { model.with(showing: :main) }
      receive_instances_of RatatuiRuby::Event, ->(_, _) { nil }
    end

    # --- Global keys ---
    # When a set tab is filtering, single-char keys must reach the filtering
    # modal rather than firing global actions. Upstream's pattern-match order
    # captures ALL single-char keys during filtering before checking CONTROLS.

    action :quit, -> { Rooibos::Command.exit }
    only when: ->(_, model) { !IsSetFiltering[nil, model] } do
      receive_events %i[q ctrl_c], :quit
      receive_events :"?", ->(_, model) { model.with(showing: :help) }
    end

    receive_events :left, lambda { |_, model|
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx - 1) % TAB_ORDER.size]
      new_tab_model, new_tab_cmd = TAB_MODULES[new_tab]::Init[]
      [model.with(active_tab: new_tab, error: nil, new_tab => new_tab_model),
       Rooibos::Command.batch(Stats::Fetch.new, new_tab_cmd)]
    }

    receive_events :right, lambda { |_, model|
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx + 1) % TAB_ORDER.size]
      new_tab_model, new_tab_cmd = TAB_MODULES[new_tab]::Init[]
      [model.with(active_tab: new_tab, error: nil, new_tab => new_tab_model),
       Rooibos::Command.batch(Stats::Fetch.new, new_tab_cmd)]
    }

    # --- Timer ---

    receive_routed :refresh, lambda { |_, model|
      [model, Rooibos::Command.batch(
        FetchCommandFor[model, model.active_tab],
        Rooibos::Command.tick(REFRESH_INTERVAL, :refresh)
      )]
    }

    # --- Data fetch results ---

    observe_instances_of Stats::Fetched, lambda { |message, model|
      model.with(stats: message.stats, stats_loading: false, redis_url: message.redis_url)
    }

    forward_instances_of Stats::Fetched, to: :home
    forward_instances_of RedisInfo::Fetched, to: :home
    forward_instances_of Processes::Fetched, to: :busy
    forward_instances_of Queues::Fetched, to: :queues
    forward_instances_of ScheduledFetched, to: :scheduled
    forward_instances_of RetriesFetched, to: :retries
    forward_instances_of DeadFetched, to: :dead
    forward_instances_of MetricsFetched, to: :metrics

    receive_instances_of DataFetchError, lambda { |message, model|
      log("DataFetchError: #{message.error_message}", *Array(message.backtrace))
      model.with(error: message)
    }

    NO_REFRESH_ACTIONS = %i[terminate quiet toggle_pause].freeze

    receive_instances_of ActionComplete, lambda { |message, model|
      DebugLogger.info("Root ActionComplete: tab=#{message.tab} action=#{message.action} succeeded=#{message.succeeded_ids.size}")
      tab = message.tab
      tab_model = model.public_send(tab)

      # Clear succeeded_ids from the nested table's selection.
      # Set tabs (scheduled/retries/dead) have .set.table; others have .table directly.
      updated = if tab_model.respond_to?(:set)
                  old_table = tab_model.set.table
                  new_table = old_table.with(selected: old_table.selected - message.succeeded_ids)
                  model.with(tab => tab_model.with(set: tab_model.set.with(table: new_table)))
                elsif tab_model.respond_to?(:table)
                  old_table = tab_model.table
                  new_table = old_table.with(selected: old_table.selected - message.succeeded_ids)
                  model.with(tab => tab_model.with(table: new_table))
                else
                  model
                end
      if NO_REFRESH_ACTIONS.include?(message.action)
        updated
      else
        [updated, FetchCommandFor[model, model.active_tab]]
      end
    }


    # When a set tab is filtering, forward raw events so the
    # filtering modal can capture keystrokes.
    IsSetFiltering = lambda { |_, model|
      SET_TABS.include?(model.active_tab) && model.public_send(model.active_tab).set.filter_model.active
    }

    only when: IsSetFiltering do
      otherwise route_to: :scheduled, when: ->(_, model) { model.active_tab == :scheduled }
      otherwise route_to: :retries,   when: ->(_, model) { model.active_tab == :retries }
      otherwise route_to: :dead,      when: ->(_, model) { model.active_tab == :dead }
    end

    (TAB_ORDER - %i[home metrics]).each do |tab|
      is_set_tab = SET_TABS.include?(tab)
      guard = ->(_, model) {
        model.active_tab == tab && !(is_set_tab && IsSetFiltering[nil, model])
      }
      only when: guard do
        route_to tab do
          TAB_MODULES[tab].key_bindings.each { |c| forward_events c.key, as: c.semantic }
        end
      end
    end

    Update = from_router

    # --- Helper lambdas ---

    FetchCommandFor = lambda { |model, tab|
      tab_model = model.public_send(tab)
      tab_module = TAB_MODULES[tab]
      Rooibos::Command.batch(Stats::Fetch.new, *tab_module::FetchCommand[tab_model])
    }

    COMMON_BINDINGS = [
      KeyBinding.new(key: nil, semantic: nil, display_key: '?', description: 'Help'),
      KeyBinding.new(key: nil, semantic: nil, display_key: '←/→', description: 'Select Tab'),
      KeyBinding.new(key: nil, semantic: nil, display_key: 'q', description: 'Quit')
    ].freeze

    ControlsForTab = lambda { |model|
      tab = model.active_tab
      tab_module = TAB_MODULES[tab]
      return COMMON_BINDINGS if model.active_tab == :home

      COMMON_BINDINGS + tab_module.key_bindings
    }

    RenderKeyBindings = lambda { |bindings, tui|
      bindings.flat_map do |binding|
        [tui.text_span(content: binding.display_key, style: Styles::HOTKEY),
         tui.text_span(content: ": #{binding.description}  ")]
      end
    }

    RenderMain = lambda { |model, tui|
      tab_bar = tui.tabs(
        titles: TAB_ORDER.map { |tab| TAB_NAMES[tab] },
        selected_index: TAB_ORDER.index(model.active_tab),
        block: tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Styles::TITLE),
        divider: ' | ', highlight_style: Styles::HIGHLIGHT
      )

      stats_keys = %w[Processed Failed Busy Enqueued Retries Scheduled Dead]
      stats_vals = if model.stats_loading
                     Array.new(7, '…')
                   else
                     [model.stats.processed, model.stats.failed, model.stats.busy, model.stats.enqueued,
                      model.stats.retries, model.stats.scheduled, model.stats.dead]
                   end
      stats = tui.paragraph(
        text: [stats_keys.map { |k| k.ljust(12) }.join('  '), stats_vals.map { |v| v.to_s.ljust(12) }.join('  ')],
        block: tui.block(title: 'Statistics', borders: [:all])
      )

      content = if model.error
                  error_msg = model.error.respond_to?(:error_message) ? model.error.error_message : model.error.to_s
                  error_bt = model.error.respond_to?(:backtrace) ? Array(model.error.backtrace) : []
                  header = [tui.text_line(
                    spans: [tui.text_span(content: error_msg, style: RatatuiRuby::Style::Style.new(modifiers: [:bold]))],
                    alignment: :center
                  )]
                  lines = error_bt.map { |line| tui.text_line(spans: [tui.text_span(content: line)]) }
                  tui.paragraph(text: header + lines, alignment: :left,
                                block: tui.block(title: 'Error', borders: [:all], border_style: Styles::ERR_BORDER))
                else
                  TAB_MODULES[model.active_tab]::View[model.public_send(model.active_tab), tui]
                end

      spans = RenderKeyBindings[ControlsForTab[model], tui]
      controls = tui.paragraph(
        text: [tui.text_line(spans: spans),
               tui.text_line(spans: [tui.text_span(content: "Redis: #{model.redis_url} "),
                                     tui.text_span(content: "Current Time: #{Time.now.utc}")])],
        block: tui.block(title: 'Controls', borders: [:all])
      )

      tui.layout(
        direction: :vertical,
        constraints: [tui.constraint_length(3), tui.constraint_length(4), tui.constraint_fill(1), tui.constraint_length(4)],
        children: [tab_bar, stats, content, controls]
      )
    }

    ESC_BINDING = KeyBinding.new(key: nil, semantic: nil, display_key: 'Esc', description: 'Close')
    HELP_BINDINGS = [ESC_BINDING, *COMMON_BINDINGS.reject { |b| b.display_key == '?' }].freeze

    RenderHelp = lambda { |_, tui|
      text_lines = [tui.text_line(spans: ['Welcome to the Sidekiq Terminal UI'], alignment: :center)] +
                   HELP_BINDINGS.map do |binding|
                     tui.text_line(spans: [tui.text_span(content: binding.display_key, style: Styles::HOTKEY),
                                           tui.text_span(content: ": #{binding.description}")])
                   end
      content = tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Styles::TITLE,
                          children: [tui.paragraph(text: text_lines)])
      ctrl = tui.paragraph(
        text: [tui.text_line(spans: [tui.text_span(content: 'Esc', style: Styles::HOTKEY),
                                     tui.text_span(content: ': Close  ')])],
        block: tui.block(title: 'Controls', borders: [:all])
      )
      tui.layout(direction: :vertical,
                 constraints: [tui.constraint_fill(1), tui.constraint_length(4)],
                 children: [content, ctrl])
    }
  end
end
