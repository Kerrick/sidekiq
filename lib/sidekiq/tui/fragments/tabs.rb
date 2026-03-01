# frozen_string_literal: true

module Sidekiq
  module TUI
    module Tabs
      include Rooibos::Router

      class ActiveTabChanged < Data.define(:tab)
        include Rooibos::Message::Predicates
      end

      Model = Data.define(:active_tab)

      Init = -> { Ractor.make_shareable(Model.new(active_tab: :home)) }

      View = lambda { |model, tui|
        tui.tabs(
          titles: TAB_ORDER.map { |tab| TAB_NAMES[tab] },
          selected_index: TAB_ORDER.index(model.active_tab),
          block: tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Styles::TITLE),
          divider: " | ", highlight_style: Styles::HIGHLIGHT
        )
      }

      SwitchTab = lambda { |index_delta, _, model|
        index = TAB_ORDER.index(model.active_tab)
        new_tab = TAB_ORDER[(index + index_delta) % TAB_ORDER.size]
        [model.with(active_tab: new_tab),
          Rooibos::Command.bubble(ActiveTabChanged.new(tab: new_tab))]
      }

      receive_routed :prev_tab, SwitchTab.curry[-1]
      receive_routed :next_tab, SwitchTab.curry[1]

      Update = from_router
    end
  end
end
