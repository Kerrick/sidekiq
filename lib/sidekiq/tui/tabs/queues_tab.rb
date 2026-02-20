# frozen_string_literal: true

module Sidekiq
  module TUI
    # Queues tab fragment. Receives semantic messages from root Router.
    module QueuesTab
      include Rooibos::Router

      Model = Data.define(:table, :pro)
      Init = -> { Ractor.make_shareable Model.new(table: EMPTY_TABLE, pro: false) }

      View = ->(model, tui, stats: EMPTY_STATS) {
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_fill(1)],
          children: [RenderStats[stats, tui], RenderQueues[model, tui]]
        )
      }

      receive_routed :row_down, RowDown
      receive_routed :row_up, RowUp
      receive_routed :toggle_select, ToggleSelect
      receive_routed :toggle_select_all, ToggleSelectAll

      receive_routed :delete_queue, ->(_, model) {
        ids = model.table.action_ids
        return model if ids.empty?
        cmds = ids.map { |qname| ClearQueue.new(queue_name: qname, tab: :queues) }
        [model.with(table: ClearSelection[model.table]), cmds.size == 1 ? cmds.first : Rooibos::Command.batch(*cmds)]
      }

      receive_routed :toggle_pause, ->(_, model) {
        ids = model.table.action_ids
        return model if ids.empty?
        cmds = ids.map { |qname| TogglePauseQueue.new(queue_name: qname, tab: :queues) }
        [model, cmds.size == 1 ? cmds.first : Rooibos::Command.batch(*cmds)]
      }

      receive_instances_of DataFetched, ->(msg, model) {
        new_table = model.table.with(rows: msg.tab_data[:rows], row_ids: msg.tab_data[:row_ids])
        model.with(table: new_table, pro: msg.tab_data[:pro] || false)
      }

      Update = from_router

      RenderQueues = ->(model, tui) {
        table = model.table
        header = ["☑️", "Queue", "Size", "Latency"]
        header << "Paused?" if model.pro
        rows = table.rows.map.with_index { |cells, idx|
          tui.table_row(
            cells: [table.selected?(table.row_ids[idx]) ? "✅" : ""] + cells,
            style: idx.even? ? nil : ALT_ROW_STYLE
          )
        }
        widths = header.map.with_index { |_, i| tui.constraint_length((i == 1) ? 60 : 10) }
        RenderTableWidget[tui, table, title: "Queues", header: header, widths: widths, rows: rows]
      }
    end
  end
end
