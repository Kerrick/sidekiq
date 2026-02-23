# frozen_string_literal: true

module Sidekiq
  module TUI
    # Reusable nested fragment for table navigation and selection.
    # Parent tabs compose via `route :table, to: TableFragment` and
    # `otherwise route_to: :table`. Navigation events are handled by
    # the table's Router; everything else is wrapped with the current
    # selection and bubbled outward as `ActionRequested`.
    module TableFragment
      include Rooibos::Router

      # Bubbled outward when the table receives a message it doesn't handle.
      class ActionRequested < Data.define(:envelope, :action, :ids)
        include Rooibos::Message::Predicates
      end

      class Model < Data.define(:row_ids, :selected, :selected_row_index)
        def selected?(id) = selected.include?(id)

        def action_ids
          if selected.empty?
            row_ids.empty? ? [] : [row_ids[selected_row_index]]
          else
            selected
          end
        end
      end

      Init = -> { Ractor.make_shareable Model.new(row_ids: [], selected: [], selected_row_index: 0) }

      # --- Navigation and selection ---

      receive_routed :row_down, lambda { |_, model|
        return model if model.row_ids.empty?

        model.with(selected_row_index: (model.selected_row_index + 1) % model.row_ids.size)
      }

      receive_routed :row_up, lambda { |_, model|
        return model if model.row_ids.empty?

        model.with(selected_row_index: (model.selected_row_index - 1) % model.row_ids.size)
      }

      receive_routed :toggle_select, lambda { |_, model|
        return model if model.row_ids.empty?

        id = model.row_ids[model.selected_row_index]
        new_selected = model.selected.include?(id) ? model.selected - [id] : model.selected + [id]
        model.with(selected: new_selected)
      }

      receive_routed :toggle_select_all, lambda { |_, model|
        return model if model.row_ids.empty?

        new_selected = model.selected.empty? ? model.row_ids.dup : []
        model.with(selected: new_selected)
      }

      # Anything the table doesn't handle as navigation gets wrapped
      # with the current selection and bubbled outward. The parent
      # intercepts ActionRequested and dispatches domain-specific commands.
      #
      # Guard: skip our own ActionRequested — the outward flow shares the
      # same receives registry, so receive_all would re-catch our bubbles.
      NotOwnBubble = ->(message, _) { !message.is_a?(ActionRequested) }

      receive NotOwnBubble, lambda { |message, model|
        ids = model.action_ids
        return model if ids.empty?

        action = message.respond_to?(:envelope) ? message.envelope : message
        DebugLogger.info("TableFragment receive_all: message=#{message.class} envelope=#{message.respond_to?(:envelope) ? message.envelope : 'N/A'} action=#{action}")
        [model, Rooibos::Command.bubble(ActionRequested.new(envelope: :table, action:, ids:))]
      }

      Update = from_router

      # --- View: renders table widget with configuration from parent ---

      View = lambda { |model, tui, title:, header:, widths:, rows:, loading: false, pager: nil, filter_state: nil|
        if loading
          SkeletonView[tui, title:, header:, widths:, pager:, filter_state:]
        else
          LoadedView[model, tui, title:, header:, widths:, rows:, pager:, filter_state:]
        end
      }

      # Skeleton view — renders placeholder … row and footer.
      # Does NOT receive model — structurally impossible to access real data.
      SkeletonView = lambda { |tui, title:, header:, widths:, pager: nil, filter_state: nil|
        footer = [""]
        if pager
          footer.push("Page: #{pager.current_page}", "Count: …", "Total: …")
        else
          footer << "Count: …"
        end

        if filter_state && filter_state[:filter]
          spans = [
            tui.text_span(content: "Filter: ", style: Views::FILTER_STYLE),
            tui.text_span(content: filter_state[:filter], style: Views::FILTER_STYLE)
          ]
          spans << tui.text_span(content: "_", style: Views::BLINK_STYLE) if filter_state[:filtering]
          footer << tui.text_line(spans: spans)
        end

        placeholder_cells = [''] + Array.new(header.size - 1, '…')
        rows = [tui.table_row(cells: placeholder_cells)]

        tui.table(
          rows: rows,
          header: header,
          widths: widths,
          column_spacing: 1,
          row_highlight_style: tui.style(fg: :white, bg: :blue),
          highlight_symbol: "➡️",
          highlight_spacing: :always,
          footer: footer,
          block: tui.block(title: title, borders: [:all])
        )
      }

      # Loaded view — renders real data.
      LoadedView = lambda { |model, tui, title:, header:, widths:, rows:, pager: nil, filter_state: nil|
        footer = [""]
        if pager
          footer.push("Page: #{pager.current_page}", "Count: #{model.row_ids.size}", "Total: #{pager.total}")
        else
          footer << "Count: #{model.row_ids.size}"
        end
        footer << "Selected: #{model.selected.size}" unless model.selected.empty?

        if filter_state && filter_state[:filter]
          spans = [
            tui.text_span(content: "Filter: ", style: Views::FILTER_STYLE),
            tui.text_span(content: filter_state[:filter], style: Views::FILTER_STYLE)
          ]
          spans << tui.text_span(content: "_", style: Views::BLINK_STYLE) if filter_state[:filtering]
          footer << tui.text_line(spans: spans)
        end

        tui.table(
          rows: rows,
          header: header,
          widths: widths,
          column_spacing: 1,
          row_highlight_style: tui.style(fg: :white, bg: :blue),
          highlight_symbol: "➡️",
          highlight_spacing: :always,
          selected_row: model.selected_row_index,
          footer: footer,
          block: tui.block(title: title, borders: [:all])
        )
      }
    end
  end
end
