# frozen_string_literal: true

module Sidekiq
  module TUI
    module ScheduledTab
      include Rooibos::Router
      include SetBehavior

      Controls = [SetBehavior::DELETE_CONTROL, SetBehavior::ENQUEUE_CONTROL,
                  SetBehavior::KILL_CONTROL, SetBehavior::FILTER_CONTROL]

      FetchCommand = ->(model) {
        [FetchScheduledSet.new(filter: model.filter, pager_page: model.pager.page, pager_size: model.pager.size)]
      }

      Model = Data.define(:table, :pager, :filter, :filtering, :tab_name, :set_class_name)

      Init = -> {
        Ractor.make_shareable Model.new(
          table: EMPTY_TABLE, pager: EMPTY_PAGER, filter: nil, filtering: false,
          tab_name: :scheduled, set_class_name: "Sidekiq::ScheduledSet"
        )
      }

      View = SetBehavior::RenderSetTable

      receive_routed :delete,  ->(_, model) { SetBehavior::MakeAlterCommand[model, :delete] }
      receive_routed :enqueue, ->(_, model) { SetBehavior::MakeAlterCommand[model, :add_to_queue] }
      receive_routed :kill,    ->(_, model) { SetBehavior::MakeAlterCommand[model, :kill] }

      receive_instances_of ScheduledFetched, SetBehavior::ApplySetData

      Update = from_router
    end
  end
end
