# frozen_string_literal: true

module Sidekiq
  module TUI
    module Queues
      include Tab

      has_table

      map :delete_queue, :shift_D, "Delete", "Delete selected queue"
      map :toggle_pause, :p, "Pause/Unpause Queue", "Pause/Unpause Queue"

      Model = Data.define(:loading, :table, :queues, :pro)
      Init = lambda {
        model = Ractor.make_shareable Model.new(loading: true, table: Table::Init[], queues: [], pro: false)
        [model, Queues::Fetch.new]
      }

      View = lambda { |model, tui|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_fill(1)],
          children: [QueuesView[model, tui]]
        )
      }

      intercept_instances_of Table::Request, lambda { |message, model|
        DebugLogger.info("Queues Request: envelope=#{message.envelope} ids=#{message.ids.inspect}")
        case message.envelope
        when :delete_queue
          [model, Queues::Clear.new(queue_names: message.ids, tab: :queues)]
        when :toggle_pause
          [model, Queues::TogglePause.new(queue_names: message.ids, tab: :queues)]
        else
          model
        end
      }

      receive_instances_of Queues::Fetched, lambda { |message, model|
        new_table = model.table.with(row_ids: message.queues.map(&:name))
        model.with(loading: false, table: new_table, queues: message.queues, pro: message.pro || false)
      }

      observe_instances_of Queues::Cleared, lambda { |_, model|
        Queues::Fetch.from_model(model)
      }
      forward_instances_of Queues::Cleared, to: :table, as: :deselect
      forward_instances_of Queues::PauseToggled, to: :table, as: :deselect

      Update = from_router

      QueuesView = lambda { |model, tui|
        table = model.table
        header = ["☑️", "Queue", "Size", "Latency"]
        header << "Paused?" if model.pro
        rows = model.queues.map.with_index do |queue_data, idx|
          cells = [table.selected?(queue_data.name) ? "✅" : "",
            queue_data.name, queue_data.size.to_s, queue_data.latency.to_s]
          cells << (queue_data.paused ? "✅" : "") if model.pro
          tui.table_row(cells: cells, style: idx.even? ? nil : Styles::ALT_ROW)
        end
        widths = header.map.with_index { |_, i| tui.constraint_length((i == 1) ? 60 : 10) }
        Table::View[table, tui, title: "Queues", header: header, widths: widths, rows: rows, loading: model.loading]
      }
    end
  end
end
