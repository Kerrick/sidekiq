# frozen_string_literal: true

module Sidekiq
  module TUI
    module Retries
      include Tab
      has_set

      map :delete,       :shift_D, 'Delete'
      map :retry,        :shift_R, 'Retry'
      map :kill,         :shift_K, 'Kill'
      map :start_filter, "/",      'Filter'

      FetchCommand = lambda { |model|
        [FetchRetrySet.new(filter: model.set.filter_model.text, pager_page: model.set.pager.page,
                           pager_size: model.set.pager.size)]
      }

      Model = Data.define(:set)

      Init = lambda {
        Ractor.make_shareable Model.new(set: Set::Init[tab_name: :retries])
      }

      View = lambda { |model, tui|
        Set::View[model.set, tui]
      }

      forward_instances_of RetriesFetched, to: :set, as: :data_received

      HandleAction = lambda { |message, model|
        DebugLogger.info("Retries HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
        case message.action
        when :delete then [model,
                           AlterSetRows.new(set_class_name: 'Sidekiq::RetrySet', ids: message.ids,
                                            action_name: :delete, tab: :retries)]
        when :retry  then [model,
                           AlterSetRows.new(set_class_name: 'Sidekiq::RetrySet', ids: message.ids, action_name: :retry,
                                            tab: :retries)]
        when :kill   then [model,
                           AlterSetRows.new(set_class_name: 'Sidekiq::RetrySet', ids: message.ids, action_name: :kill,
                                            tab: :retries)]
        else model
        end
      }
      intercept_instances_of Table::ActionRequested, HandleAction

      HandleFetch = lambda { |message, model|
        DebugLogger.info("Retries HandleFetch: filter=#{message.filter} page=#{message.pager_page}")
        [model,
         FetchRetrySet.new(filter: message.filter, pager_page: message.pager_page, pager_size: message.pager_size)]
      }
      intercept_instances_of Set::FetchRequested, HandleFetch

      Update = from_router
    end
  end
end
