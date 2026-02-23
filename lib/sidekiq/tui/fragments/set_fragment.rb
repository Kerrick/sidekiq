# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared sorted-set fragment, nested inside each set tab.
    # Handles pagination, table rendering, and selection.
    # Filtering is delegated to FilterFragment.
    # Parent tabs forward semantic data messages with `as: :data_received`
    # and intercept bubbles for domain-specific dispatch.
    module SetFragment
      include Rooibos::Router

      # Bubbled when pagination changes — parent intercepts and issues tab-specific fetch.
      class FetchRequested < Data.define(:envelope, :filter, :pager_page, :pager_size)
        include Rooibos::Message::Predicates
      end

      Model = Data.define(:loading, :table, :pager, :rows, :filter_model, :tab_name)

      Init = lambda { |tab_name:|
        Ractor.make_shareable Model.new(
          loading: true, table: TableFragment::Init[], pager: PagerState::EMPTY, rows: [],
          filter_model: FilterFragment::Init[], tab_name: tab_name
        )
      }

      # --- Nested fragments ---

      route :table, to: TableFragment
      route :filter_model, to: FilterFragment

      # Forward start_filter to FilterFragment
      forward_routed :start_filter, to: :filter_model, as: :start_filter

      # When filtering is active, forward all unmatched events to FilterFragment
      # so it can capture keystrokes.
      only when: ->(_, model) { model.filter_model.active } do
        otherwise route_to: :filter_model
      end

      # When not filtering, unmatched events go to the table for navigation/selection.
      otherwise route_to: :table

      # --- Data arrival (forwarded from parent with as: :data_received) ---

      ApplyData = lambda { |message, model|
        data = message.event # the original ScheduledFetched / RetriesFetched / DeadFetched
        DebugLogger.info("SetFragment ApplyData: event_class=#{data.class} row_ids=#{data.row_ids.size}")
        new_table = model.table.with(row_ids: data.row_ids)
        new_pager = model.pager.with(
          current_page: data.current_page, total: data.total,
          next_page: data.next_page, page: data.pager_page, size: data.pager_size
        )
        model.with(loading: false, table: new_table, pager: new_pager, rows: data.rows)
      }
      receive_routed :data_received, ApplyData

      # --- FilterFragment intercepts ---
      # When FilterFragment signals a filter change, clear selection, reset page, and re-fetch.

      intercept_instances_of FilterFragment::FilterChanged, lambda { |message, model|
        DebugLogger.info("SetFragment FilterChanged: text=#{message.text}")
        new_table = model.table.with(selected: [])
        new_model = model.with(table: new_table)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: message.text,
                             pager_page: 1, pager_size: new_model.pager.size)
        )]
      }

      # --- Pagination (bubbles FetchRequested for parent to intercept) ---

      PrevPage = lambda { |_, model|
        return model unless model.pager.has_prev?

        DebugLogger.info("SetFragment PrevPage: page=#{model.pager.page - 1}")
        new_pager = model.pager.with(page: model.pager.page - 1)
        new_model = model.with(pager: new_pager)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: model.filter_model.text,
                             pager_page: new_model.pager.page, pager_size: new_model.pager.size)
        )]
      }

      NextPage = lambda { |_, model|
        return model unless model.pager.has_next?

        DebugLogger.info("SetFragment NextPage: page=#{model.pager.next_page}")
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
        filter_state = { filter: model.filter_model.text, filtering: model.filter_model.active }
        rows = model.rows.map.with_index do |entry, idx|
          tui.table_row(
            cells: [model.table.selected?(entry[:id]) ? '✅' : '',
                    entry[:at], entry[:queue], entry[:display_class], entry[:display_args]],
            style: idx.even? ? nil : Views::ALT_ROW_STYLE
          )
        end
        TableFragment::View[model.table, tui,
                            title: TAB_NAMES[model.tab_name], rows: rows, pager: model.pager,
                            filter_state: filter_state, loading: model.loading,
                            header: ['☑️', 'When', 'Queue', 'Job', 'Arguments'],
                            widths: [tui.constraint_length(5), tui.constraint_length(24), tui.constraint_length(20),
                                     tui.constraint_length(30), tui.constraint_fill(1)]]
      }
    end
  end
end
