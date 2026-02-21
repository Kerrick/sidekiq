# frozen_string_literal: true

module Sidekiq
  module TUI
    module QueuesTab
      include Rooibos::Router

      Controls = [
        TabControl.new(key: :shift_D, semantic: :delete_queue, display_key: "D", description: "Delete"),
        TabControl.new(key: :p, semantic: :toggle_pause, display_key: "p", description: "Pause/Unpause")
      ]
      FetchCommand = ->(_model) { [FetchQueues.new] }

      Model = Data.define(:table, :queues, :pro)
      Init = -> { Ractor.make_shareable Model.new(table: TableFragment::Init[], queues: [], pro: false) }

      View = ->(model, tui, stats: EMPTY_STATS) {
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_fill(1)],
          children: [Views::RenderStats[stats, tui], RenderQueues[model, tui]]
        )
      }

      route :table, to: TableFragment
      otherwise route_to: :table

      intercept_instances_of TableFragment::ActionRequested, ->(message, model) {
        DebugLogger.info("QueuesTab HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
        case message.action
        when :delete_queue
          commands = message.ids.map { |qname| ClearQueue.new(queue_name: qname, tab: :queues) }
          [model, commands.size == 1 ? commands.first : Rooibos::Command.batch(*commands)]
        when :toggle_pause
          commands = message.ids.map { |qname| TogglePauseQueue.new(queue_name: qname, tab: :queues) }
          [model, commands.size == 1 ? commands.first : Rooibos::Command.batch(*commands)]
        else
          model
        end
      }

      receive_instances_of QueuesFetched, ->(message, model) {
        new_table = model.table.with(row_ids: message.queues.map(&:name))
        model.with(table: new_table, queues: message.queues, pro: message.pro || false)
      }

      Update = from_router

      RenderQueues = ->(model, tui) {
        table = model.table
        header = ["☑️", "Queue", "Size", "Latency"]
        header << "Paused?" if model.pro
        rows = model.queues.map.with_index { |queue_data, idx|
          cells = [table.selected?(queue_data.name) ? "✅" : "",
                   queue_data.name, queue_data.size.to_s, queue_data.latency.to_s]
          cells << (queue_data.paused ? "✅" : "") if model.pro
          tui.table_row(cells: cells, style: idx.even? ? nil : Views::ALT_ROW_STYLE)
        }
        widths = header.map.with_index { |_, i| tui.constraint_length((i == 1) ? 60 : 10) }
        TableFragment::View[table, tui, title: "Queues", header: header, widths: widths, rows: rows]
      }
    end
  end
end
