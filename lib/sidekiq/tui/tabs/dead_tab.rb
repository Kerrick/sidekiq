# frozen_string_literal: true

module Sidekiq
  module TUI
    module DeadTab
      include Rooibos::Router
      include SetBehavior

      Controls = [SetBehavior::DELETE_CONTROL, SetBehavior::ENQUEUE_CONTROL,
                  SetBehavior::FILTER_CONTROL]

      FetchCommand = ->(model) {
        [FetchDeadSet.new(filter: model.filter, pager_page: model.pager.page, pager_size: model.pager.size)]
      }

      Model = Data.define(:table, :pager, :rows, :filter, :filtering, :tab_name, :set_class_name)

      Init = -> {
        Ractor.make_shareable Model.new(
          table: TableFragment::Init[], pager: EMPTY_PAGER, rows: [],
          filter: nil, filtering: false,
          tab_name: :dead, set_class_name: "Sidekiq::DeadSet"
        )
      }

      View = SetBehavior::RenderSetTable

      receive_routed :delete,  ->(_, model) { SetBehavior::MakeAlterCommand[model, :delete] }
      receive_routed :enqueue, ->(_, model) { SetBehavior::MakeAlterCommand[model, :add_to_queue] }

      receive_instances_of DeadFetched, SetBehavior::ApplySetData

      Update = from_router
    end
  end
end
