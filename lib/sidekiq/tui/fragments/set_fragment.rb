# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared sorted-set fragment, nested inside each set tab.
    # Handles filtering, pagination, table rendering, and selection.
    # Parent tabs forward semantic data messages with `as: :data_received`
    # and intercept bubbles for domain-specific dispatch.
    module SetFragment
      include Rooibos::Router

      # Bubbled when pagination changes — parent intercepts and issues tab-specific fetch.
      class FetchRequested < Data.define(:envelope, :filter, :pager_page, :pager_size)
        include Rooibos::Message::Predicates
      end

      Model = Data.define(:table, :pager, :rows, :filter, :filtering, :tab_name)

      Init = ->(tab_name:) {
        Ractor.make_shareable Model.new(
          table: TableFragment::Init[], pager: EMPTY_PAGER, rows: [],
          filter: nil, filtering: false, tab_name: tab_name
        )
      }

      # --- Nested table ---

      route :table, to: TableFragment
      otherwise route_to: :table

      # --- Data arrival (forwarded from parent with as: :data_received) ---

      ApplyData = ->(message, model) {
        data = message.event # the original ScheduledFetched / RetriesFetched / DeadFetched
        new_table = model.table.with(row_ids: data.row_ids)
        new_pager = model.pager.with(
          current_page: data.current_page, total: data.total,
          next_page: data.next_page, page: data.pager_page, size: data.pager_size
        )
        model.with(table: new_table, pager: new_pager, rows: data.rows)
      }
      receive_routed :data_received, ApplyData

      # --- Filtering ---

      StartFilter = ->(_, model) { model.with(filtering: true, filter: "") }
      IsFiltering = ->(_, model) { model.filtering }
      IsTextInput = ->(message, _) { message.respond_to?(:text?) && message.text? && message.code.length == 1 }
      AppendChar = ->(message, model) { model.with(filter: "#{model.filter}#{message.code}") }
      Backspace = ->(_, model) { model.with(filter: (model.filter || "").chop) }
      SubmitFilter = ->(_, model) { model.with(filtering: false) }
      CancelFilter = ->(_, model) { model.with(filtering: false, filter: nil) }

      receive_routed :start_filter, StartFilter

      only when: IsFiltering do
        receive IsTextInput, AppendChar
        receive_events :backspace, Backspace
        receive_events :enter, SubmitFilter
        receive_events :esc, CancelFilter
      end

      # --- Pagination (bubbles FetchRequested for parent to intercept) ---

      PrevPage = ->(_, model) {
        return model if model.pager.page < 2
        new_pager = model.pager.with(page: model.pager.page - 1)
        new_model = model.with(pager: new_pager)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: new_model.filter,
                             pager_page: new_model.pager.page, pager_size: new_model.pager.size)
        )]
      }

      NextPage = ->(_, model) {
        return model unless model.pager.next_page
        new_pager = model.pager.with(page: model.pager.next_page)
        new_model = model.with(pager: new_pager)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: new_model.filter,
                             pager_page: new_model.pager.page, pager_size: new_model.pager.size)
        )]
      }

      receive_routed :prev_page, PrevPage
      receive_routed :next_page, NextPage

      Update = from_router

      # --- View ---

      View = ->(model, tui, stats: EMPTY_STATS) {
        filter_state = { filter: model.filter, filtering: model.filtering }
        rows = model.rows.map.with_index { |entry, idx|
          tui.table_row(
            cells: [model.table.selected?(entry[:id]) ? "✅" : "",
                    entry[:at], entry[:queue], entry[:display_class], entry[:display_args]],
            style: idx.even? ? nil : Views::ALT_ROW_STYLE
          )
        }
        table_widget = TableFragment::View[model.table, tui,
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
    end
  end
end
