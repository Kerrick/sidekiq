# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared sorted-set fragment, nested inside each set tab.
    # Handles pagination, table rendering, and selection.
    # Filtering is delegated to Filter.
    # Parent tabs forward data messages with `as: :data_received`
    # and intercept bubbles for domain-specific dispatch.
    module SetContent
      include Tab

      # Bubbled when pagination changes — parent intercepts and issues tab-specific fetch.
      class FetchRequested < Data.define(:envelope, :filter, :pager_page, :pager_size)
        include Rooibos::Message::Predicates
      end

      Model = Data.define(:loading, :table, :pager, :rows, :filter_model, :tab_name)

      Init = lambda { |tab_name:|
        Ractor.make_shareable Model.new(
          loading: true, table: Table::Init[], pager: PagerState::EMPTY, rows: [],
          filter_model: Filter::Init[], tab_name: tab_name
        )
      }

      # --- Nested fragments ---

      route :table, to: Table
      has_filter on_changed: ->(message, model) {
        new_table = model.table.with(selected: [])
        new_model = model.with(table: new_table)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: message.text,
            pager_page: 1, pager_size: new_model.pager.size)
        )]
      }

      # When not filtering, unmatched events go to the table for navigation/selection.
      otherwise route_to: :table

      # --- Data arrival (forwarded from parent with as: :data_received) ---

      ApplyData = lambda { |message, model|
        data = message.event # the original Scheduled::Fetched / Retry::Fetched / Dead::Fetched
        new_table = model.table.with(row_ids: data.row_ids)
        new_pager = model.pager.with(
          current_page: data.current_page, total: data.total,
          next_page: data.next_page, page: data.pager_page, size: data.pager_size
        )
        model.with(loading: false, table: new_table, pager: new_pager, rows: data.rows)
      }
      receive_routed :data_received, ApplyData

      forward_routed :rows_altered, to: :table, as: :deselect

      # --- Pagination (bubbles FetchRequested for parent to intercept) ---

      PrevPage = lambda { |_, model|
        return model unless model.pager.has_prev?

        new_pager = model.pager.with(page: model.pager.page - 1)
        new_model = model.with(pager: new_pager)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: model.filter_model.text,
            pager_page: new_model.pager.page, pager_size: new_model.pager.size)
        )]
      }

      NextPage = lambda { |_, model|
        return model unless model.pager.has_next?

        new_pager = model.pager.with(page: model.pager.next_page)
        new_model = model.with(pager: new_pager)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: model.filter_model.text,
            pager_page: new_model.pager.page, pager_size: new_model.pager.size)
        )]
      }

      receive_routed :prev_page, PrevPage
      receive_routed :next_page, NextPage

      Update = from_router

      # --- View ---

      View = lambda { |model, tui|
        rows = model.rows.map.with_index do |entry, idx|
          tui.table_row(
            cells: [model.table.selected?(entry.id) ? "✅" : "",
              entry.at, entry.queue, entry.display_class, entry.display_args],
            style: idx.even? ? nil : Styles::ALT_ROW
          )
        end
        Table::View[model.table, tui,
          title: Tabs::TAB_NAMES[model.tab_name], rows: rows, pager: model.pager,
          loading: model.loading,
          header: ["☑️", "When", "Queue", "Job", "Arguments"],
          widths: [tui.constraint_length(5), tui.constraint_length(24), tui.constraint_length(20),
            tui.constraint_length(30), tui.constraint_fill(1)]]
      }
    end
  end
end
