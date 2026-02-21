# frozen_string_literal: true

module Sidekiq
  module TUI
    module DeadTab
      include Rooibos::Router

      Controls = [
        TabControl.new(key: :shift_D, semantic: :delete,       display_key: 'D', description: 'Delete'),
        TabControl.new(key: :shift_E, semantic: :enqueue,      display_key: 'E', description: 'Enqueue'),
        TabControl.new(key: :"/",     semantic: :start_filter, display_key: '/', description: 'Filter')
      ].freeze

      FetchCommand = lambda { |model|
        [FetchDeadSet.new(filter: model.set.filter, pager_page: model.set.pager.page,
                          pager_size: model.set.pager.size)]
      }

      Model = Data.define(:set)

      Init = lambda {
        Ractor.make_shareable Model.new(set: SetFragment::Init[tab_name: :dead])
      }

      View = lambda { |model, tui, stats: EMPTY_STATS|
        SetFragment::View[model.set, tui, stats:]
      }

      route :set, to: SetFragment
      otherwise route_to: :set

      forward_instances_of DeadFetched, to: :set, as: :data_received

      HandleAction = lambda { |message, model|
        DebugLogger.info("DeadTab HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
        case message.action
        when :delete  then [model,
                            AlterSetRows.new(set_class_name: 'Sidekiq::DeadSet', ids: message.ids,
                                             action_name: :delete, tab: :dead)]
        when :enqueue then [model,
                            AlterSetRows.new(set_class_name: 'Sidekiq::DeadSet', ids: message.ids,
                                             action_name: :add_to_queue, tab: :dead)]
        else model
        end
      }
      intercept_instances_of TableFragment::ActionRequested, HandleAction

      HandleFetch = lambda { |message, model|
        DebugLogger.info("DeadTab HandleFetch: filter=#{message.filter} page=#{message.pager_page}")
        [model,
         FetchDeadSet.new(filter: message.filter, pager_page: message.pager_page, pager_size: message.pager_size)]
      }
      intercept_instances_of SetFragment::FetchRequested, HandleFetch

      Update = from_router
    end
  end
end
