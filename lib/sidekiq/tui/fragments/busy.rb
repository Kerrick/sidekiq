# frozen_string_literal: true

module Sidekiq
  module TUI
    module Busy
      include Rooibos::Router

      Controls = [
        TabControl.new(key: :shift_T, semantic: :terminate, display_key: 'T', description: 'Terminate'),
        TabControl.new(key: :shift_Q, semantic: :quiet, display_key: 'Q', description: 'Quiet')
      ].freeze
      FetchCommand = ->(_model) { [Processes::Fetch.new] }

      class Model < Data.define(:loading, :table, :processes, :work_set_size)
        def total_concurrency = processes.sum(&:concurrency)
        def total_rss = processes.sum(&:rss_kb)

        def utilization
          total_concurrency.zero? ? 0.0 : (work_set_size.to_f / total_concurrency * 100).round(1)
        end
      end

      Init = lambda {
        Ractor.make_shareable Model.new(loading: true, table: TableFragment::Init[], processes: [], work_set_size: 0)
      }

      View = lambda { |model, tui|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_fill(1)],
          children: [RenderStatus[model, tui], RenderProcesses[model, tui]]
        )
      }

      route :table, to: TableFragment
      otherwise route_to: :table

      intercept_instances_of TableFragment::ActionRequested, lambda { |message, model|
        DebugLogger.info("Busy HandleAction: action=#{message.action} ids=#{message.ids.inspect}")
        case message.action
        when :terminate
          [model, SignalProcess.new(identities: message.ids, signal: :terminate, tab: :busy)]
        when :quiet
          [model, SignalProcess.new(identities: message.ids, signal: :quiet, tab: :busy)]
        else
          model
        end
      }

      receive_instances_of Processes::Fetched, lambda { |message, model|
        DebugLogger.info("Busy ProcessesFetched: #{message.processes.size} processes")
        new_table = model.table.with(row_ids: message.processes.map(&:identity))
        model.with(loading: false, table: new_table, processes: message.processes, work_set_size: message.work_set_size)
      }

      Update = from_router

      RenderStatus = lambda { |model, tui|
        keys = %w[Processes Threads Busy Utilization RSS]
        vals = if model.loading
                 Array.new(5, '…')
               else
                 [model.processes.size, model.total_concurrency, model.work_set_size,
                  "#{model.utilization}%", Views::FormatMemory[model.total_rss]]
               end
        tui.paragraph(
          text: [keys.map { |k| k.ljust(12) }.join('  '), vals.map { |v| v.to_s.ljust(12) }.join('  ')],
          block: tui.block(title: 'Status', borders: [:all])
        )
      }

      RenderProcesses = lambda { |model, tui|
        table = model.table
        rows = model.processes.map.with_index do |process, idx|
          display_name = process.name
          display_name += ' ⭐️' if process.leader
          display_name += ' 🛑' if process.stopping
          cells = [table.selected?(process.identity) ? '✅' : '',
                   display_name, process.started_at.to_s, Views::FormatMemory[process.rss_kb],
                   process.concurrency.to_s, process.busy.to_s]
          tui.table_row(cells: cells, style: idx.even? ? nil : Views::ALT_ROW_STYLE)
        end
        TableFragment::View[table, tui, title: 'Processes',
                                        header: ['☑️', 'Name', 'Started', 'RSS', 'Threads', 'Busy'],
                                        widths: [tui.constraint_length(5), tui.constraint_fill(1), tui.constraint_length(24),
                                                 tui.constraint_length(10), tui.constraint_length(6), tui.constraint_length(6)],
                                        rows: rows, loading: model.loading]
      }
    end
  end
end
