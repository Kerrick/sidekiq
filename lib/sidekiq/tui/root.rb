# frozen_string_literal: true

module Sidekiq
  module TUI
    include Rooibos::Router

    TAB_ORDER = %i[home busy queues scheduled retry dead metrics].freeze
    TAB_NAMES = {
      home: "Home", busy: "Busy", queues: "Queues", scheduled: "Scheduled",
      retry: "Retries", dead: "Dead", metrics: "Metrics"
    }.freeze
    SET_TABS = %i[scheduled retry dead].freeze

    TAB_MODULES = {
      home: Home, busy: Busy, queues: Queues, scheduled: Scheduled,
      retry: Retry, dead: Dead, metrics: Metrics
    }.freeze

    Model = Data.define(
      :tabs, :stats, :help, :error,
      :home, :busy, :queues, :scheduled, :retry, :dead, :metrics
    )

    Init = lambda {
      tick = Rooibos::Command.tick(1, :clock)
      home_model, home_cmd = Home::Init[]
      stats_model, stats_cmd = Stats::Init[]
      help_model, _help_cmd = Help::Init[]
      model = Ractor.make_shareable Model.new(
        tabs: Tabs::Init[],
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
      tab_bar = Tabs::View[model.tabs, tui]
      stats_view = Stats::View[model.stats, tui]
      content = if model.error
        ErrorView[model.error, tui]
      else
        TAB_MODULES[model.tabs.active_tab]::View[model.public_send(model.tabs.active_tab), tui]
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
        block: tui.block(title: "Error", borders: [:all], border_style: Styles::ERR_BORDER))
    }

    # --- Fragment routes ---

    route :tabs, to: Tabs
    route :stats, to: Stats
    route :home, to: Home
    route :busy, to: Busy
    route :queues, to: Queues
    route :scheduled, to: Scheduled
    route :retry, to: Retry
    route :dead, to: Dead
    route :metrics, to: Metrics
    route :help, to: Help

    # --- Help overlay (modal — swallows all events) ---

    only when: ->(_, model) { model.help.expanded } do
      receive_events %i[esc ?], ->(_, model) { model.with(help: model.help.with(expanded: false)) }
      receive_instances_of RatatuiRuby::Event, ->(_, _) {}
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

    route_to :tabs do
      forward_events :left, as: :prev_tab
      forward_events :right, as: :next_tab
    end

    observe_instances_of Tabs::ActiveTabChanged, lambda { |message, model|
      new_tab = message.tab
      new_tab_model, new_tab_cmd = TAB_MODULES[new_tab]::Init[]
      [model.with(error: nil, new_tab => new_tab_model),
        Rooibos::Command.batch(Stats::Fetch.new, new_tab_cmd)]
    }

    # --- Timer ---

    observe_instances_of Rooibos::Message::Timer, lambda { |_, model|
      cmds = [Rooibos::Command.tick(1, :clock)]
      cmds << FetchCommandFor[model, model.tabs.active_tab] if Time.now.to_i.even?
      [model, Rooibos::Command.batch(*cmds)]
    }

    forward_instances_of Rooibos::Message::Timer, broadcast: true, as: :clock

    # --- Data fetch results ---

    forward_instances_of Stats::Fetched, broadcast_to: [:stats, :home, :help]

    route_to :home do
      forward_instances_of RedisInfo::Fetched
    end
    route_to :busy do
      forward_instances_of Busy::Fetched
      forward_instances_of Busy::Signaled
    end
    route_to :queues do
      forward_instances_of Queues::Fetched
      forward_instances_of Queues::Cleared
      forward_instances_of Queues::PauseToggled
    end
    route_to :scheduled do
      forward_instances_of Scheduled::Fetched
      forward ->(msg, _) { msg.is_a?(SetRows::Altered) && msg.tab == :scheduled }
    end
    route_to :retry do
      forward_instances_of Retry::Fetched
      forward ->(msg, _) { msg.is_a?(SetRows::Altered) && msg.tab == :retry }
    end
    route_to :dead do
      forward_instances_of Dead::Fetched
      forward ->(msg, _) { msg.is_a?(SetRows::Altered) && msg.tab == :dead }
    end
    route_to :metrics do
      forward_instances_of Metrics::Fetched
    end

    receive_instances_of DataFetchError, lambda { |message, model|
      log("DataFetchError: #{message.error_message}", *Array(message.backtrace))
      model.with(error: message)
    }

    # When a set tab is filtering, forward raw events so the
    # filtering modal can capture keystrokes.
    IsSetFiltering = lambda { |_, model|
      SET_TABS.include?(model.tabs.active_tab) && model.public_send(model.tabs.active_tab).set.filter_model.active
    }

    only when: IsSetFiltering do
      otherwise route_to: :scheduled, when: ->(_, model) { model.tabs.active_tab == :scheduled }
      otherwise route_to: :retry, when: ->(_, model) { model.tabs.active_tab == :retry }
      otherwise route_to: :dead, when: ->(_, model) { model.tabs.active_tab == :dead }
    end

    (TAB_ORDER - %i[home metrics]).each do |tab|
      is_set_tab = SET_TABS.include?(tab)
      guard = ->(_, model) {
        model.tabs.active_tab == tab && !(is_set_tab && IsSetFiltering[nil, model])
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
      tab_module = TAB_MODULES[tab]
      Rooibos::Command.batch(Stats::Fetch.new, *tab_module::Fetch.from_model(model.public_send(tab)))
    }
  end
end
