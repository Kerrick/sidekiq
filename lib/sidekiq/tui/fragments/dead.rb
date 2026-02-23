# frozen_string_literal: true

module Sidekiq
  module TUI
    module Dead
      include Tab
      has_set

      map :delete,       :shift_D, 'Delete'
      map :enqueue,      :shift_E, 'Enqueue'
      map :start_filter, "/",      'Filter'

      FetchCommand = lambda { |model|
        [FetchDeadSet.new(filter: model.set.filter_model.text, pager_page: model.set.pager.page,
                          pager_size: model.set.pager.size)]
      }

      Model = Data.define(:set)

      Init = lambda {
        Ractor.make_shareable Model.new(set: SetFragment::Init[tab_name: :dead])
      }

      View = lambda { |model, tui|
        SetFragment::View[model.set, tui]
      }

      forward_instances_of DeadFetched, to: :set, as: :data_received

      HandleAction = lambda { |message, model|
        DebugLogger.info("Dead HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
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
        DebugLogger.info("Dead HandleFetch: filter=#{message.filter} page=#{message.pager_page}")
        [model,
         FetchDeadSet.new(filter: message.filter, pager_page: message.pager_page, pager_size: message.pager_size)]
      }
      intercept_instances_of SetFragment::FetchRequested, HandleFetch

      Update = from_router
    end
  end
end
