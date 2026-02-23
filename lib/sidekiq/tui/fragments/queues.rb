# frozen_string_literal: true

module Sidekiq
  module TUI
    module Queues
      include Rooibos::Router

      Controls = [
        TabControl.new(key: :shift_D, semantic: :delete_queue, display_key: 'D', description: 'Delete'),
        TabControl.new(key: :p, semantic: :toggle_pause, display_key: 'p', description: 'Pause/Unpause Queue')
      ].freeze
      FetchCommand = ->(_model) { [Queues::Fetch.new] }

      Model = Data.define(:loading, :table, :queues, :pro)
      Init = -> { Ractor.make_shareable Model.new(loading: true, table: TableFragment::Init[], queues: [], pro: false) }

      View = lambda { |model, tui|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_fill(1)],
          children: [RenderQueues[model, tui]]
        )
      }

      route :table, to: TableFragment
      otherwise route_to: :table

      intercept_instances_of TableFragment::ActionRequested, lambda { |message, model|
        DebugLogger.info("Queues HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
        case message.action
        when :delete_queue
          [model, ClearQueue.new(queue_names: message.ids, tab: :queues)]
        when :toggle_pause
          [model, TogglePauseQueue.new(queue_names: message.ids, tab: :queues)]
        else
          model
        end
      }

      receive_instances_of Queues::Fetched, lambda { |message, model|
        new_table = model.table.with(row_ids: message.queues.map(&:name))
        model.with(loading: false, table: new_table, queues: message.queues, pro: message.pro || false)
      }

      Update = from_router

      RenderQueues = lambda { |model, tui|
        table = model.table
        header = ['☑️', 'Queue', 'Size', 'Latency']
        header << 'Paused?' if model.pro
        rows = model.queues.map.with_index do |queue_data, idx|
          cells = [table.selected?(queue_data.name) ? '✅' : '',
                   queue_data.name, queue_data.size.to_s, queue_data.latency.to_s]
          cells << (queue_data.paused ? '✅' : '') if model.pro
          tui.table_row(cells: cells, style: idx.even? ? nil : Views::ALT_ROW_STYLE)
        end
        widths = header.map.with_index { |_, i| tui.constraint_length(i == 1 ? 60 : 10) }
        TableFragment::View[table, tui, title: 'Queues', header: header, widths: widths, rows: rows, loading: model.loading]
      }
    end
  end
end
