# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared behavior for sorted set tabs (Scheduled, Retries, Dead).
    # Include in each individual set tab fragment.
    module SetBehavior
      # --- Shared controls ---

      DELETE_CONTROL  = TabControl.new(key: :shift_D, semantic: :delete,       display_key: "D", description: "Delete")
      RETRY_CONTROL   = TabControl.new(key: :shift_R, semantic: :retry,        display_key: "R", description: "Retry")
      ENQUEUE_CONTROL = TabControl.new(key: :shift_E, semantic: :enqueue,      display_key: "E", description: "Enqueue")
      KILL_CONTROL    = TabControl.new(key: :shift_K, semantic: :kill,          display_key: "K", description: "Kill")
      FILTER_CONTROL  = TabControl.new(key: :"/",     semantic: :start_filter, display_key: "/", description: "Filter")

      # --- Shared update logic ---

      MakeAlterCommand = ->(model, action_name) {
        ids = model.table.action_ids
        return model if ids.empty?
        command = AlterSetRows.new(set_class_name: model.set_class_name, ids: ids,
                                   action_name:, tab: model.tab_name)
        [model.with(table: Actions::ClearSelection[model.table]), command]
      }

      ApplySetData = ->(message, model) {
        new_table = model.table.with(rows: message.rows, row_ids: message.row_ids)
        new_pager = model.pager.with(
          current_page: message.current_page, total: message.total,
          next_page: message.next_page, page: message.pager_page, size: message.pager_size
        )
        model.with(table: new_table, pager: new_pager)
      }

      StartFilter = ->(_, model) { model.with(filtering: true, filter: "") }

      # --- Shared view rendering ---

      RenderSetTable = ->(model, tui, stats: EMPTY_STATS) {
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

      # --- Shared Router declarations (called when included) ---

      def self.included(base)
        base.module_eval do
          receive_routed :row_down, Actions::RowDown
          receive_routed :row_up, Actions::RowUp
          receive_routed :toggle_select, Actions::ToggleSelect
          receive_routed :toggle_select_all, Actions::ToggleSelectAll
          receive_routed :start_filter, SetBehavior::StartFilter

          receive_routed :prev_page, ->(_, model) {
            return model if model.pager.page < 2
            new_pager = model.pager.with(page: model.pager.page - 1)
            new_model = model.with(pager: new_pager)
            [new_model, base::FetchCommand[new_model].first]
          }

          receive_routed :next_page, ->(_, model) {
            return model unless model.pager.next_page
            new_pager = model.pager.with(page: model.pager.next_page)
            new_model = model.with(pager: new_pager)
            [new_model, base::FetchCommand[new_model].first]
          }

          # Filtering modal
          only when: ->(_, model) { model.filtering } do
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
        end
      end
    end
  end
end
