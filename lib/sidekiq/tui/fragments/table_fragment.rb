# frozen_string_literal: true

module Sidekiq
  module TUI
    # Reusable nested fragment for table navigation and selection.
    # Parent tabs compose via `route :table, to: TableFragment` and
    # forward navigation events. Parents own the raw data and format
    # rows for display; the table handles cursor + selection state.
    module TableFragment
      include Rooibos::Router

      class Model < Data.define(:row_ids, :selected, :selected_row_index)
        def selected?(id) = selected.include?(id)

        def action_ids
          selected.empty? ? (row_ids.empty? ? [] : [row_ids[selected_row_index]]) : selected
        end
      end

      Init = -> { Ractor.make_shareable Model.new(row_ids: [], selected: [], selected_row_index: 0) }

      # --- Navigation and selection ---

      receive_routed :row_down, ->(_, model) {
        return model if model.row_ids.empty?
        model.with(selected_row_index: (model.selected_row_index + 1) % model.row_ids.size)
      }

      receive_routed :row_up, ->(_, model) {
        return model if model.row_ids.empty?
        model.with(selected_row_index: (model.selected_row_index - 1) % model.row_ids.size)
      }

      receive_routed :toggle_select, ->(_, model) {
        return model if model.row_ids.empty?
        id = model.row_ids[model.selected_row_index]
        new_selected = model.selected.include?(id) ? model.selected - [id] : model.selected + [id]
        model.with(selected: new_selected)
      }

      receive_routed :toggle_select_all, ->(_, model) {
        return model if model.row_ids.empty?
        new_selected = model.selected.size == model.row_ids.size ? [] : model.row_ids.dup
        model.with(selected: new_selected)
      }

      Update = from_router

      ClearSelection = ->(model) { model.with(selected: [], selected_row_index: 0) }

      # --- View: renders table widget with configuration from parent ---

      View = ->(model, tui, title:, header:, widths:, rows:, pager: nil, filter_state: nil) {
        highlight = tui.style(fg: :cyan, add_modifier: :bold)
        count_text = "Count: #{model.row_ids.size}"
        count_text += " | Page: #{pager.current_page}" if pager
        count_text += " | Filter: #{filter_state[:filter]}" if filter_state && filter_state[:filter]

        tui.table(
          rows: rows,
          header: tui.table_row(cells: header, style: tui.style(fg: :cyan, add_modifier: :bold)),
          widths: widths,
          column_spacing: 1,
          row_highlight_style: highlight,
          highlight_symbol: " ▶ ",
          selected: model.selected_row_index,
          block: tui.block(title: "#{title} (#{count_text})", borders: [:all])
        )
      }
    end
  end
end
