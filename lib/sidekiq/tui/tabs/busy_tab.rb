# frozen_string_literal: true

module Sidekiq
  module TUI
    module BusyTab
      include Rooibos::Router

      Model = Data.define(:table, :status)

      Init = -> {
        Ractor.make_shareable Model.new(table: EMPTY_TABLE, status: EMPTY_BUSY_STATUS)
      }

      View = ->(model, tui, stats: EMPTY_STATS) {
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_length(4), tui.constraint_fill(1)],
          children: [RenderStats[stats, tui], RenderStatus[model.status, tui], RenderProcesses[model.table, tui]]
        )
      }

      receive_routed :row_down, RowDown
      receive_routed :row_up, RowUp
      receive_routed :toggle_select, ToggleSelect
      receive_routed :toggle_select_all, ToggleSelectAll

      receive_routed :terminate, ->(_, model) {
        commands = model.table.action_ids.map { |id| SignalProcess.new(identity: id, signal: :terminate, tab: :busy) }
        return model if commands.empty?
        [model.with(table: ClearSelection[model.table]), commands.size == 1 ? commands.first : Rooibos::Command.batch(*commands)]
      }

      receive_routed :quiet, ->(_, model) {
        commands = model.table.action_ids.map { |id| SignalProcess.new(identity: id, signal: :quiet, tab: :busy) }
        return model if commands.empty?
        [model, commands.size == 1 ? commands.first : Rooibos::Command.batch(*commands)]
      }

      receive_instances_of DataFetched, ->(message, model) {
        new_table = model.table.with(rows: message.tab_data[:rows], row_ids: message.tab_data[:row_ids])
        model.with(table: new_table, status: message.tab_data[:status])
      }

      Update = from_router

      RenderStatus = ->(status, tui) {
        keys = %w[Processes Threads Busy Utilization RSS]
        vals = [status.processes, status.threads, status.busy, status.utilization, status.rss]
        tui.paragraph(
          text: [keys.map { |k| k.ljust(12) }.join("  "), vals.map { |v| v.to_s.ljust(12) }.join("  ")],
          block: tui.block(title: "Status", borders: [:all])
        )
      }

      RenderProcesses = ->(table, tui) {
        rows = table.rows.map.with_index { |cells, idx|
          tui.table_row(
            cells: [table.selected?(table.row_ids[idx]) ? "✅" : ""] + cells,
            style: idx.even? ? nil : ALT_ROW_STYLE
          )
        }
        RenderTableWidget[tui, table, title: "Processes",
          header: ["☑️", "Name", "Started", "RSS", "Threads", "Busy"],
          widths: [tui.constraint_length(5), tui.constraint_fill(1), tui.constraint_length(24),
                   tui.constraint_length(10), tui.constraint_length(6), tui.constraint_length(6)],
          rows: rows]
      }
    end
  end
end
