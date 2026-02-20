# frozen_string_literal: true

module Sidekiq
  module TUI
    # Reusable set tab fragment — one module, three routes (scheduled, retries, dead).
    # Configurable via model fields (tab_name, set_class_name, allowed_actions).
    module SetTab
      include Rooibos::Router

      Model = Data.define(:table, :pager, :filter, :filtering,
                          :tab_name, :set_class_name, :allowed_actions)

      Init = ->(tab_name:, set_class_name:, allowed_actions:) {
        Ractor.make_shareable Model.new(
          table: EMPTY_TABLE, pager: EMPTY_PAGER, filter: nil, filtering: false,
          tab_name:, set_class_name:, allowed_actions:
        )
      }

      View = ->(model, tui, stats: EMPTY_STATS) {
        filter_state = { filter: model.filter, filtering: model.filtering }
        rows = model.table.rows.map.with_index { |entry, idx|
          tui.table_row(
            cells: [model.table.selected?(entry[:id]) ? "✅" : "",
                    entry[:at], entry[:queue], entry[:display_class], entry[:display_args]],
            style: idx.even? ? nil : Views::ALT_ROW_STYLE
          )
        }
        table_widget = Views::RenderTableWidget[tui, model.table,
          title: TAB_NAMES[model.tab_name], rows: rows, pager: model.pager, filter_state: filter_state,
          header: ["☑️", "When", "Queue", "Job", "Arguments"],
          widths: [tui.constraint_length(5), tui.constraint_length(24), tui.constraint_length(20),
                   tui.constraint_length(30), tui.constraint_fill(1)]]
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_fill(1)],
          children: [Views::RenderStats[stats, tui], table_widget]
        )
      }

      # --- Semantic messages from root ---

      receive_routed :row_down, Actions::RowDown
      receive_routed :row_up, Actions::RowUp
      receive_routed :toggle_select, Actions::ToggleSelect
      receive_routed :toggle_select_all, Actions::ToggleSelectAll

      receive_routed :prev_page, ->(_, model) {
        return model if model.pager.page < 2
        new_pager = model.pager.with(page: model.pager.page - 1)
        new_model = model.with(pager: new_pager)
        [new_model, FetchSet.new(tab: model.tab_name, set_class_name: model.set_class_name,
                                 filter: model.filter, pager_page: new_pager.page, pager_size: new_pager.size)]
      }

      receive_routed :next_page, ->(_, model) {
        return model unless model.pager.next_page
        new_pager = model.pager.with(page: model.pager.next_page)
        new_model = model.with(pager: new_pager)
        [new_model, FetchSet.new(tab: model.tab_name, set_class_name: model.set_class_name,
                                 filter: model.filter, pager_page: new_pager.page, pager_size: new_pager.size)]
      }

      receive_routed :start_filter, ->(_, model) { model.with(filtering: true, filter: "") }

      # --- Guarded destructive actions ---

      ALLOWS_DELETE  = ->(_, model) { model.allowed_actions.include?(:delete) }
      ALLOWS_RETRY   = ->(_, model) { model.allowed_actions.include?(:retry) }
      ALLOWS_ENQUEUE = ->(_, model) { model.allowed_actions.include?(:add_to_queue) }
      ALLOWS_KILL    = ->(_, model) { model.allowed_actions.include?(:kill) }

      MakeAlterCommand = ->(model, action_name) {
        ids = model.table.action_ids
        return model if ids.empty?
        command = AlterSetRows.new(set_class_name: model.set_class_name, ids: ids,
                                   action_name:, tab: model.tab_name)
        [model.with(table: Actions::ClearSelection[model.table]), command]
      }

      receive_routed :delete,  ->(_, model) { MakeAlterCommand[model, :delete] },      guard: ALLOWS_DELETE
      receive_routed :retry,   ->(_, model) { MakeAlterCommand[model, :retry] },       guard: ALLOWS_RETRY
      receive_routed :enqueue, ->(_, model) { MakeAlterCommand[model, :add_to_queue] }, guard: ALLOWS_ENQUEUE
      receive_routed :kill,    ->(_, model) { MakeAlterCommand[model, :kill] },         guard: ALLOWS_KILL

      # --- Filtering modal: raw events forwarded by root when filtering is active ---

      FILTERING_ACTIVE = ->(_, model) { model.filtering }

      only when: FILTERING_ACTIVE do
        receive ->(message, _) { message.respond_to?(:text?) && message.text? && message.code.length == 1 },
          ->(message, model) { model.with(filter: "#{model.filter}#{message.code}") }

        receive_events :backspace, ->(_, model) {
          model.with(filter: (model.filter || "").chop)
        }

        receive_events :enter, ->(_, model) {
          model.with(filtering: false, table: Actions::ClearSelection[model.table])
        }

        receive_events :esc, ->(_, model) {
          model.with(filtering: false, filter: nil, table: Actions::ClearSelection[model.table])
        }
      end

      # --- Data integration ---

      receive_instances_of DataFetched, ->(message, model) {
        new_table = model.table.with(rows: message.tab_data[:rows], row_ids: message.tab_data[:row_ids])
        new_pager = model.pager.with(
          current_page: message.tab_data[:current_page], total: message.tab_data[:total],
          next_page: message.tab_data[:next_page], page: message.tab_data[:pager_page], size: message.tab_data[:pager_size]
        )
        model.with(table: new_table, pager: new_pager)
      }

      Update = from_router
    end
  end
end
