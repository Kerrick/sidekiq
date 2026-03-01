# frozen_string_literal: true

module Sidekiq
  module TUI
    module Tabs
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

      class ActiveTabChanged < Data.define(:tab)
        include Rooibos::Message::Predicates
      end

      Model = Data.define(
        :active_tab,
        :home, :busy, :queues, :scheduled, :retry, :dead, :metrics
      )

      Init = lambda {
        home_model, home_cmd = Home::Init[]
        model = Ractor.make_shareable Model.new(
          active_tab: :home,
          home: home_model,
          busy: Busy::Init[].first,
          queues: Queues::Init[].first,
          scheduled: Scheduled::Init[].first,
          retry: Retry::Init[].first,
          dead: Dead::Init[].first,
          metrics: Metrics::Init[].first
        )
        [model, home_cmd]
      }

      View = lambda { |model, tui, stats_slot|
        tab_bar = tui.tabs(
          titles: TAB_ORDER.map { |tab| TAB_NAMES[tab] },
          selected_index: TAB_ORDER.index(model.active_tab),
          block: tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Styles::TITLE),
          divider: " | ", highlight_style: Styles::HIGHLIGHT
        )
        content = TAB_MODULES[model.active_tab]::View[model.public_send(model.active_tab), tui]
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(3), tui.constraint_length(4), tui.constraint_fill(1)],
          children: [tab_bar, stats_slot, content]
        )
      }

      SwitchTab = lambda { |direction, _, model|
        idx = TAB_ORDER.index(model.active_tab)
        new_tab = TAB_ORDER[(idx + direction) % TAB_ORDER.size]
        new_tab_model, new_tab_cmd = TAB_MODULES[new_tab]::Init[]
        [model.with(active_tab: new_tab, new_tab => new_tab_model),
          Rooibos::Command.batch(
            Rooibos::Command.bubble(ActiveTabChanged.new(tab: new_tab)),
            new_tab_cmd)]
      }

      receive_routed :prev_tab, SwitchTab.curry[-1]
      receive_routed :next_tab, SwitchTab.curry[1]

      observe_routed :clock, lambda { |_, model|
        if Time.now.to_i.even?
          [model, FetchCommandFor[model, model.active_tab]]
        end
      }
      forward_routed :clock, broadcast: true

      route :home, to: Home
      route :busy, to: Busy
      route :queues, to: Queues
      route :scheduled, to: Scheduled
      route :retry, to: Retry
      route :dead, to: Dead
      route :metrics, to: Metrics

      route_to :home do
        forward_instances_of Stats::Fetched
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

      IsSetFiltering = lambda { |_, model|
        SET_TABS.include?(model.active_tab) && model.public_send(model.active_tab).set.filter_model.active
      }

      only when: IsSetFiltering do
        otherwise route_to: :scheduled, when: ->(_, model) { model.active_tab == :scheduled }
        otherwise route_to: :retry, when: ->(_, model) { model.active_tab == :retry }
        otherwise route_to: :dead, when: ->(_, model) { model.active_tab == :dead }
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

      FetchCommandFor = lambda { |model, tab|
        TAB_MODULES[tab]::Fetch.from_model(model.public_send(tab))
      }

      Update = from_router
    end
  end
end
