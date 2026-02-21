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
        DebugLogger.info("SetFragment ApplyData: event_class=#{data.class} row_ids=#{data.row_ids.size}")
        new_table = model.table.with(row_ids: data.row_ids)
        new_pager = model.pager.with(
          current_page: data.current_page, total: data.total,
          next_page: data.next_page, page: data.pager_page, size: data.pager_size
        )
        model.with(table: new_table, pager: new_pager, rows: data.rows)
      }
      receive_routed :data_received, ApplyData

      # --- Filtering ---

      receive_routed :start_filter, ->(_, model) {
        DebugLogger.info("SetFragment StartFilter")
        model.with(filtering: true, filter: "")
      }

      only when: ->(_, model) { model.filtering } do
        receive ->(message, _) { message.respond_to?(:text?) && message.text? && message.code.length == 1 },
          ->(message, model) {
            DebugLogger.info("SetFragment AppendChar: #{message.code}")
            model.with(filter: "#{model.filter}#{message.code}")
          }
        receive_events :backspace, ->(_, model) { model.with(filter: (model.filter || "").chop) }
        receive_events :enter, ->(_, model) {
          DebugLogger.info("SetFragment SubmitFilter: filter=#{model.filter}")
          new_model = model.with(filtering: false)
          [new_model, Rooibos::Command.bubble(
            FetchRequested.new(envelope: :set, filter: new_model.filter,
                               pager_page: 1, pager_size: new_model.pager.size)
          )]
        }
        receive_events :esc, ->(_, model) {
          DebugLogger.info("SetFragment CancelFilter")
          new_model = model.with(filtering: false, filter: nil)
          [new_model, Rooibos::Command.bubble(
            FetchRequested.new(envelope: :set, filter: nil,
                               pager_page: 1, pager_size: new_model.pager.size)
          )]
        }
      end

      # --- Pagination (bubbles FetchRequested for parent to intercept) ---

      PrevPage = ->(_, model) {
        return model if model.pager.page < 2
        DebugLogger.info("SetFragment PrevPage: page=#{model.pager.page - 1}")
        new_pager = model.pager.with(page: model.pager.page - 1)
        new_model = model.with(pager: new_pager)
        [new_model, Rooibos::Command.bubble(
          FetchRequested.new(envelope: :set, filter: new_model.filter,
                             pager_page: new_model.pager.page, pager_size: new_model.pager.size)
        )]
      }

      NextPage = ->(_, model) {
        return model unless model.pager.next_page
        DebugLogger.info("SetFragment NextPage: page=#{model.pager.next_page}")
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
