# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared action lambdas — semantic message handlers reused across table fragments.
    module Actions
      RowDown = ->(_, model) {
        return model if model.table.row_ids.empty?
        model.with(table: model.table.with(selected_row_index: (model.table.selected_row_index + 1) % model.table.row_ids.size))
      }

      RowUp = ->(_, model) {
        return model if model.table.row_ids.empty?
        model.with(table: model.table.with(selected_row_index: (model.table.selected_row_index - 1) % model.table.row_ids.size))
      }

      ToggleSelect = ->(_, model) {
        table = model.table
        return model if table.row_ids.empty?
        id = table.row_ids[table.selected_row_index]
        new_sel = table.selected.include?(id) ? table.selected - [id] : table.selected + [id]
        model.with(table: table.with(selected: new_sel))
      }

      ToggleSelectAll = ->(_, model) {
        table = model.table
        model.with(table: table.with(selected: table.selected.empty? ? table.row_ids.dup : []))
      }

      ClearSelection = ->(table) { table.with(selected: []) }
    end
  end
end
