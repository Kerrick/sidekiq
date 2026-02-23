# frozen_string_literal: true

module Sidekiq
  module TUI
    module RetriesTab
      include Rooibos::Router

      Controls = [
        TabControl.new(key: :shift_D, semantic: :delete,       display_key: 'D', description: 'Delete'),
        TabControl.new(key: :shift_R, semantic: :retry,        display_key: 'R', description: 'Retry'),
        TabControl.new(key: :shift_K, semantic: :kill, display_key: 'K', description: 'Kill'),
        TabControl.new(key: :"/",     semantic: :start_filter, display_key: '/', description: 'Filter')
      ].freeze

      FetchCommand = lambda { |model|
        [FetchRetrySet.new(filter: model.set.filter_model.text, pager_page: model.set.pager.page,
                           pager_size: model.set.pager.size)]
      }

      Model = Data.define(:set)

      Init = lambda {
        Ractor.make_shareable Model.new(set: SetFragment::Init[tab_name: :retries])
      }

      View = lambda { |model, tui|
        SetFragment::View[model.set, tui]
      }

      route :set, to: SetFragment
      otherwise route_to: :set

      forward_instances_of RetriesFetched, to: :set, as: :data_received

      HandleAction = lambda { |message, model|
        DebugLogger.info("RetriesTab HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
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
      intercept_instances_of TableFragment::ActionRequested, HandleAction

      HandleFetch = lambda { |message, model|
        DebugLogger.info("RetriesTab HandleFetch: filter=#{message.filter} page=#{message.pager_page}")
        [model,
         FetchRetrySet.new(filter: message.filter, pager_page: message.pager_page, pager_size: message.pager_size)]
      }
      intercept_instances_of SetFragment::FetchRequested, HandleFetch

      Update = from_router
    end
  end
end
