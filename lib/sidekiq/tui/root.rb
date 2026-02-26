# frozen_string_literal: true

module Sidekiq
  module TUI
    include Rooibos::Router

    REFRESH_INTERVAL = 2.0

    TAB_ORDER = %i[home busy queues scheduled retry dead metrics].freeze
    TAB_NAMES = {
      home: 'Home', busy: 'Busy', queues: 'Queues', scheduled: 'Scheduled',
      retry: 'Retries', dead: 'Dead', metrics: 'Metrics'
    }.freeze
    SET_TABS = %i[scheduled retry dead].freeze

    TAB_MODULES = {
      home: Home, busy: Busy, queues: Queues, scheduled: Scheduled,
      retry: Retry, dead: Dead, metrics: Metrics
    }.freeze

    Model = Data.define(
      :active_tab, :stats, :help, :error,
      :home, :busy, :queues, :scheduled, :retry, :dead, :metrics
    )

    Init = lambda {
      tick = Rooibos::Command.tick(REFRESH_INTERVAL, :refresh)
      home_model, home_cmd = Home::Init[]
      stats_model, stats_cmd = Stats::Init[]
      help_model, _help_cmd = Help::Init[]
      model = Ractor.make_shareable Model.new(
        active_tab: :home,
        stats: stats_model, help: help_model, error: nil,
        home: home_model,
        busy: Busy::Init[].first,
        queues: Queues::Init[].first,
        scheduled: Scheduled::Init[].first,
        retry: Retry::Init[].first,
        dead: Dead::Init[].first,
        metrics: Metrics::Init[].first
      )
      [model, Rooibos::Command.batch(stats_cmd, home_cmd, tick)]
    }

    View = lambda { |model, tui|
      tab_bar = tui.tabs(
        titles: TAB_ORDER.map { |tab| TAB_NAMES[tab] },
        selected_index: TAB_ORDER.index(model.active_tab),
        block: tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Styles::TITLE),
        divider: ' | ', highlight_style: Styles::HIGHLIGHT
      )
      stats_view = Stats::View[model.stats, tui]
      content = if model.error
                  ErrorView[model.error, tui]
                else
                  TAB_MODULES[model.active_tab]::View[model.public_send(model.active_tab), tui]
                end
      controls = Help::ControlsView[model.help, tui]
      base = tui.layout(
        direction: :vertical,
        constraints: [tui.constraint_length(3), tui.constraint_length(4), tui.constraint_fill(1), tui.constraint_length(4)],
        children: [tab_bar, stats_view, content, controls]
      )
      Help::View[model.help, tui, base]
    }

    ErrorView = lambda { |error, tui|
      error_msg = error.respond_to?(:error_message) ? error.error_message : error.to_s
      error_bt = error.respond_to?(:backtrace) ? Array(error.backtrace) : []
      header = [tui.text_line(
        spans: [tui.text_span(content: error_msg, style: RatatuiRuby::Style::Style.new(modifiers: [:bold]))],
        alignment: :center
      )]
      lines = error_bt.map { |line| tui.text_line(spans: [tui.text_span(content: line)]) }
      tui.paragraph(text: header + lines, alignment: :left,
                    block: tui.block(title: 'Error', borders: [:all], border_style: Styles::ERR_BORDER))
    }

    # --- Fragment routes ---

    route :home, to: Home
    route :busy, to: Busy
    route :queues, to: Queues
    route :scheduled, to: Scheduled
    route :retry, to: Retry
    route :dead, to: Dead
    route :metrics, to: Metrics

    # --- Help overlay (modal — swallows all events) ---

    only when: ->(_, model) { model.help.expanded } do
      receive_events %i[esc ?], ->(_, model) { model.with(help: model.help.with(expanded: false)) }
      receive_instances_of RatatuiRuby::Event, ->(_, _) { nil }
    end

    # --- Global keys ---
    # When a set tab is filtering, single-char keys must reach the filtering
    # modal rather than firing global actions. Upstream's pattern-match order
    # captures ALL single-char keys during filtering before checking CONTROLS.

    action :quit, -> { Rooibos::Command.exit }
    only when: ->(_, model) { !IsSetFiltering[nil, model] } do
      receive_events %i[q ctrl_c], :quit
      receive_events :"?", ->(_, model) { model.with(help: model.help.with(expanded: true)) }
    end

    receive_events :left, lambda { |_, model|
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx - 1) % TAB_ORDER.size]
      new_tab_model, new_tab_cmd = TAB_MODULES[new_tab]::Init[]
      [model.with(active_tab: new_tab, error: nil, new_tab => new_tab_model,
                  help: model.help.with(active_tab: new_tab)),
       Rooibos::Command.batch(Stats::Fetch.new, new_tab_cmd)]
    }

    receive_events :right, lambda { |_, model|
      idx = TAB_ORDER.index(model.active_tab)
      new_tab = TAB_ORDER[(idx + 1) % TAB_ORDER.size]
      new_tab_model, new_tab_cmd = TAB_MODULES[new_tab]::Init[]
      [model.with(active_tab: new_tab, error: nil, new_tab => new_tab_model,
                  help: model.help.with(active_tab: new_tab)),
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
      new_stats = Stats::Update[message, model.stats]
      model.with(stats: new_stats, help: model.help.with(redis_url: new_stats.redis_url))
    }

    forward_instances_of Stats::Fetched, to: :home
    forward_instances_of RedisInfo::Fetched, to: :home
    forward_instances_of Busy::Fetched, to: :busy
    forward_instances_of Queues::Fetched, to: :queues
    forward_instances_of Scheduled::Fetched, to: :scheduled
    forward_instances_of Retry::Fetched, to: :retry
    forward_instances_of Dead::Fetched, to: :dead
    forward_instances_of Metrics::Fetched, to: :metrics

    receive_instances_of DataFetchError, lambda { |message, model|
      log("DataFetchError: #{message.error_message}", *Array(message.backtrace))
      model.with(error: message)
    }

    receive_instances_of SetRowsAltered, lambda { |message, model|
      tab_model = model.public_send(message.tab)
      old_table = tab_model.set.table
      new_table = old_table.with(selected: old_table.selected - message.succeeded_ids)
      updated = model.with(message.tab => tab_model.with(set: tab_model.set.with(table: new_table)))
      [updated, FetchCommandFor[model, model.active_tab]]
    }

    receive_instances_of ProcessSignaled, lambda { |message, model|
      old_table = model.busy.table
      new_table = old_table.with(selected: old_table.selected - message.succeeded_ids)
      model.with(busy: model.busy.with(table: new_table))
    }

    receive_instances_of QueueCleared, lambda { |message, model|
      old_table = model.queues.table
      new_table = old_table.with(selected: old_table.selected - message.succeeded_ids)
      updated = model.with(queues: model.queues.with(table: new_table))
      [updated, FetchCommandFor[model, model.active_tab]]
    }

    receive_instances_of QueuePauseToggled, lambda { |message, model|
      old_table = model.queues.table
      new_table = old_table.with(selected: old_table.selected - message.succeeded_ids)
      model.with(queues: model.queues.with(table: new_table))
    }


    # When a set tab is filtering, forward raw events so the
    # filtering modal can capture keystrokes.
    IsSetFiltering = lambda { |_, model|
      SET_TABS.include?(model.active_tab) && model.public_send(model.active_tab).set.filter_model.active
    }

    only when: IsSetFiltering do
      otherwise route_to: :scheduled, when: ->(_, model) { model.active_tab == :scheduled }
      otherwise route_to: :retry,     when: ->(_, model) { model.active_tab == :retry }
      otherwise route_to: :dead,      when: ->(_, model) { model.active_tab == :dead }
    end

    (TAB_ORDER - %i[home metrics]).each do |tab|
      is_set_tab = SET_TABS.include?(tab)
      guard = ->(_, model) {
        model.active_tab == tab && !(is_set_tab && IsSetFiltering[nil, model])
      }
      only when: guard do
        route_to tab do
          TAB_MODULES[tab].key_bindings.each { |c| forward_events c.key, as: c.envelope }
        end
      end
    end

    Update = from_router

    # --- Helper lambdas ---

    FetchCommandFor = lambda { |model, tab|
      tab_model = model.public_send(tab)
      tab_module = TAB_MODULES[tab]
      Rooibos::Command.batch(Stats::Fetch.new, *tab_module::Fetch.from_model(tab_model))
    }


  end
end
