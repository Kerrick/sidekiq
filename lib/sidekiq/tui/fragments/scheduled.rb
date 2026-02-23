# frozen_string_literal: true

module Sidekiq
  module TUI
    module Scheduled
      include Tab
      has_set

      map :delete,       :shift_D, 'Delete'
      map :enqueue,      :shift_E, 'Enqueue'
      map :kill,         :shift_K, 'Kill'
      map :start_filter, "/",      'Filter'

      FetchCommand = lambda { |model|
        [FetchScheduledSet.new(filter: model.set.filter_model.text, pager_page: model.set.pager.page,
                               pager_size: model.set.pager.size)]
      }

      Model = Data.define(:set)

      Init = lambda {
        model = Ractor.make_shareable Model.new(set: Set::Init[tab_name: :scheduled])
        [model, FetchScheduledSet.new(filter: '', pager_page: 1, pager_size: 25)]
      }

      View = lambda { |model, tui|
        Set::View[model.set, tui]
      }

      # Inward: forward semantic data message to Set
      forward_instances_of ScheduledFetched, to: :set, as: :data_received

      # Outward: intercept action bubbles from Table
      HandleAction = lambda { |message, model|
        DebugLogger.info("Scheduled HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
        case message.action
        when :delete  then [model,
                            AlterSetRows.new(set_class_name: 'Sidekiq::ScheduledSet', ids: message.ids,
                                             action_name: :delete, tab: :scheduled)]
        when :enqueue then [model,
                            AlterSetRows.new(set_class_name: 'Sidekiq::ScheduledSet', ids: message.ids, action_name: :add_to_queue,
                                             tab: :scheduled)]
        when :kill    then [model,
                            AlterSetRows.new(set_class_name: 'Sidekiq::ScheduledSet', ids: message.ids,
                                             action_name: :kill, tab: :scheduled)]
        else model
        end
      }
      intercept_instances_of Table::ActionRequested, HandleAction

      # Outward: intercept pagination bubbles from Set
      HandleFetch = lambda { |message, model|
        DebugLogger.info("Scheduled HandleFetch: filter=#{message.filter} page=#{message.pager_page}")
        [model,
         FetchScheduledSet.new(filter: message.filter, pager_page: message.pager_page, pager_size: message.pager_size)]
      }
      intercept_instances_of Set::FetchRequested, HandleFetch

      Update = from_router
    end
  end
end
