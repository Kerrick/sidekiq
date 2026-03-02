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
      TABLE_TABS = %i[busy queues scheduled retry dead].freeze
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
        home_model, home_command = Home::Init[]
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
        [model, home_command]
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

      SwitchTab = lambda { |index_delta, _, model|
        index = TAB_ORDER.index(model.active_tab)
        new_tab = TAB_ORDER[(index + index_delta) % TAB_ORDER.size]
        new_tab_model, new_tab_command = TAB_MODULES[new_tab]::Init[]
        [model.with(active_tab: new_tab, new_tab => new_tab_model),
          Rooibos::Command.batch(
            Rooibos::Command.bubble(ActiveTabChanged.new(tab: new_tab)),
            new_tab_command)]
      }
      receive_routed :prev_tab, SwitchTab.curry[-1]
      receive_routed :next_tab, SwitchTab.curry[1]

      observe_routed :clock, lambda { |_, model|
        if Time.now.to_i.even?
          tab = model.active_tab
          command = TAB_MODULES[tab]::Fetch.from_model(model.public_send(tab))
          [model, command]
        end
      }
      forward_routed :clock, broadcast: true

      TAB_MESSAGES = {
        home:      [Stats::Fetched, RedisInfo::Fetched],
        busy:      [Busy::Fetched, Busy::Signaled],
        queues:    [Queues::Fetched, Queues::Cleared, Queues::PauseToggled],
        scheduled: [Scheduled::Fetched],
        retry:     [Retry::Fetched],
        dead:      [Dead::Fetched],
        metrics:   [Metrics::Fetched]
      }.freeze
      TAB_MESSAGES.keys.each { |tab| route tab, to: TAB_MODULES[tab] }
      TAB_MESSAGES.each do |tab, message_classes|
        route_to tab do
          message_classes.each { |c| forward_instances_of c }
        end
      end
      SET_TABS.each do |tab|
        forward ->(msg, _) { msg.is_a?(SetRows::Altered) && msg.tab == tab }, to: tab
      end

      IsSetFiltering = lambda { |_, model|
        SET_TABS.include?(model.active_tab) &&
          model.public_send(model.active_tab).filtering?
      }
      only when: IsSetFiltering do
        SET_TABS.each do |tab|
          otherwise route_to: tab, when: ->(_, model) { model.active_tab == tab }
        end
      end

      TABLE_TABS.each do |tab|
        is_set_tab = SET_TABS.include?(tab)
        is_active_and_accepts_keys = ->(_, model) {
          model.active_tab == tab && !(is_set_tab && IsSetFiltering[nil, model])
        }
        only when: is_active_and_accepts_keys do
          route_to tab do
            (KeyMap::TABLE + KeyMap::FOR_TAB[tab]).each { |b| forward_events b.key, as: b.envelope }
          end
        end
      end

      Update = from_router
    end
  end
end
