# frozen_string_literal: true

module Sidekiq
  module TUI
    module BusyTab
      include Rooibos::Router

      Controls = [
        TabControl.new(key: :shift_T, semantic: :terminate, display_key: "T", description: "Terminate"),
        TabControl.new(key: :shift_Q, semantic: :quiet, display_key: "Q", description: "Quiet")
      ]
      FetchCommand = ->(_model) { [FetchProcesses.new] }

      Model = Data.define(:table, :processes, :work_set_size)

      Init = -> {
        Ractor.make_shareable Model.new(table: EMPTY_TABLE, processes: [], work_set_size: 0)
      }

      View = ->(model, tui, stats: EMPTY_STATS) {
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_length(4), tui.constraint_fill(1)],
          children: [Views::RenderStats[stats, tui], RenderStatus[model, tui], RenderProcesses[model, tui]]
        )
      }

      receive_routed :row_down, Actions::RowDown
      receive_routed :row_up, Actions::RowUp
      receive_routed :toggle_select, Actions::ToggleSelect
      receive_routed :toggle_select_all, Actions::ToggleSelectAll

      receive_routed :terminate, ->(_, model) {
        commands = model.table.action_ids.map { |id| SignalProcess.new(identity: id, signal: :terminate, tab: :busy) }
        return model if commands.empty?
        [model.with(table: Actions::ClearSelection[model.table]), commands.size == 1 ? commands.first : Rooibos::Command.batch(*commands)]
      }

      receive_routed :quiet, ->(_, model) {
        commands = model.table.action_ids.map { |id| SignalProcess.new(identity: id, signal: :quiet, tab: :busy) }
        return model if commands.empty?
        [model, commands.size == 1 ? commands.first : Rooibos::Command.batch(*commands)]
      }

      receive_instances_of ProcessesFetched, ->(message, model) {
        new_table = model.table.with(row_ids: message.processes.map(&:identity))
        model.with(table: new_table, processes: message.processes, work_set_size: message.work_set_size)
      }

      Update = from_router

      RenderStatus = ->(model, tui) {
        total_concurrency = model.processes.sum(&:concurrency)
        total_rss = model.processes.sum(&:rss_kb)
        utilization = (total_concurrency == 0) ? "0%" : "#{((model.work_set_size / total_concurrency.to_f) * 100).round(0)}%"

        keys = %w[Processes Threads Busy Utilization RSS]
        vals = [model.processes.size.to_s, total_concurrency.to_s, model.work_set_size.to_s,
                utilization, Views::FormatMemory[total_rss]]
        tui.paragraph(
          text: [keys.map { |k| k.ljust(12) }.join("  "), vals.map { |v| v.to_s.ljust(12) }.join("  ")],
          block: tui.block(title: "Status", borders: [:all])
        )
      }

      RenderProcesses = ->(model, tui) {
        table = model.table
        rows = model.processes.map.with_index { |process_data, idx|
          name = "#{process_data.hostname}:#{process_data.pid}"
          name += " ⭐️" if process_data.leader
          name += " 🛑" if process_data.stopping
          cells = [table.selected?(process_data.identity) ? "✅" : "",
                   name, process_data.started_at.to_s, Views::FormatMemory[process_data.rss_kb],
                   process_data.concurrency.to_s, process_data.busy.to_s]
          tui.table_row(cells: cells, style: idx.even? ? nil : Views::ALT_ROW_STYLE)
        }
        Views::RenderTableWidget[tui, table, title: "Processes",
          header: ["☑️", "Name", "Started", "RSS", "Threads", "Busy"],
          widths: [tui.constraint_length(5), tui.constraint_fill(1), tui.constraint_length(24),
                   tui.constraint_length(10), tui.constraint_length(6), tui.constraint_length(6)],
          rows: rows]
      }
    end
  end
end
