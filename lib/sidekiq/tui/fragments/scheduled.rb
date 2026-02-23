# frozen_string_literal: true

module Sidekiq
  module TUI
    module Scheduled
      include Rooibos::Router

      Controls = [
        TabControl.new(key: :shift_D, semantic: :delete,       display_key: 'D', description: 'Delete'),
        TabControl.new(key: :shift_E, semantic: :enqueue,      display_key: 'E', description: 'Enqueue'),
        TabControl.new(key: :shift_K, semantic: :kill,         display_key: 'K', description: 'Kill'),
        TabControl.new(key: :"/",     semantic: :start_filter, display_key: '/', description: 'Filter')
      ].freeze

      FetchCommand = lambda { |model|
        [FetchScheduledSet.new(filter: model.set.filter_model.text, pager_page: model.set.pager.page,
                               pager_size: model.set.pager.size)]
      }

      Model = Data.define(:set)

      Init = lambda {
        Ractor.make_shareable Model.new(set: SetFragment::Init[tab_name: :scheduled])
      }

      View = lambda { |model, tui|
        SetFragment::View[model.set, tui]
      }

      route :set, to: SetFragment
      otherwise route_to: :set

      # Inward: forward semantic data message to SetFragment
      forward_instances_of ScheduledFetched, to: :set, as: :data_received

      # Outward: intercept action bubbles from TableFragment
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
      intercept_instances_of TableFragment::ActionRequested, HandleAction

      # Outward: intercept pagination bubbles from SetFragment
      HandleFetch = lambda { |message, model|
        DebugLogger.info("Scheduled HandleFetch: filter=#{message.filter} page=#{message.pager_page}")
        [model,
         FetchScheduledSet.new(filter: message.filter, pager_page: message.pager_page, pager_size: message.pager_size)]
      }
      intercept_instances_of SetFragment::FetchRequested, HandleFetch

      Update = from_router
    end
  end
end
