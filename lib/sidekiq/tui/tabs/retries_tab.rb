# frozen_string_literal: true

module Sidekiq
  module TUI
    module RetriesTab
      include Rooibos::Router
      include SetBehavior

      Controls = [SetBehavior::DELETE_CONTROL, SetBehavior::RETRY_CONTROL,
                  SetBehavior::KILL_CONTROL, SetBehavior::FILTER_CONTROL]

      FetchCommand = ->(model) {
        [FetchRetrySet.new(filter: model.filter, pager_page: model.pager.page, pager_size: model.pager.size)]
      }

      Model = Data.define(:table, :pager, :filter, :filtering, :tab_name, :set_class_name)

      Init = -> {
        Ractor.make_shareable Model.new(
          table: EMPTY_TABLE, pager: EMPTY_PAGER, filter: nil, filtering: false,
          tab_name: :retries, set_class_name: "Sidekiq::RetrySet"
        )
      }

      View = SetBehavior::RenderSetTable

      receive_routed :delete, ->(_, model) { SetBehavior::MakeAlterCommand[model, :delete] }
      receive_routed :retry,  ->(_, model) { SetBehavior::MakeAlterCommand[model, :retry] }
      receive_routed :kill,   ->(_, model) { SetBehavior::MakeAlterCommand[model, :kill] }

      receive_instances_of RetriesFetched, SetBehavior::ApplySetData

      Update = from_router
    end
  end
end
