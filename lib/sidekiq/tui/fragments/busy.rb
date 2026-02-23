# frozen_string_literal: true

module Sidekiq
  module TUI
    module Busy
      include Tab
      has_table
      fetch_command Processes::Fetch

      map :terminate, :shift_T, 'Terminate'
      map :quiet,     :shift_Q, 'Quiet'

      class Model < Data.define(:loading, :table, :processes, :work_set_size)
        def total_concurrency = processes.sum(&:concurrency)
        def total_rss = processes.sum(&:rss_kb)

        def utilization
          total_concurrency.zero? ? 0.0 : (work_set_size.to_f / total_concurrency * 100).round(1)
        end

        def formatted_total_rss
          rss_kb = total_rss
          return '0' if rss_kb.zero?

          if rss_kb < 100_000
            "#{rss_kb} KB"
          elsif rss_kb < 10_000_000
            "#{(rss_kb / 1024.0).to_i} MB"
          else
            "#{(rss_kb / (1024.0 * 1024.0)).round(1)} GB"
          end
        end
      end

      Init = lambda {
        model = Ractor.make_shareable Model.new(loading: true, table: Table::Init[], processes: [], work_set_size: 0)
        [model, Processes::Fetch.new]
      }

      View = lambda { |model, tui|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_fill(1)],
          children: [StatusView[model, tui], ProcessesView[model, tui]]
        )
      }

      intercept_instances_of Table::ActionRequested, lambda { |message, model|
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

      StatusView = lambda { |model, tui|
        keys = %w[Processes Threads Busy Utilization RSS]
        vals = if model.loading
                 Array.new(5, '…')
               else
                 [model.processes.size, model.total_concurrency, model.work_set_size,
                  "#{model.utilization}%", model.formatted_total_rss]
               end
        tui.paragraph(
          text: [keys.map { |k| k.ljust(12) }.join('  '), vals.map { |v| v.to_s.ljust(12) }.join('  ')],
          block: tui.block(title: 'Status', borders: [:all])
        )
      }

      ProcessesView = lambda { |model, tui|
        table = model.table
        rows = model.processes.map.with_index do |process, idx|
          display_name = process.name
          display_name = "#{process.name} ⭐️" if process.leader
          display_name = "#{process.name} 🛑" if process.stopping
          cells = [table.selected?(process.identity) ? '✅' : '',
                   display_name, process.started_at.to_s, process.formatted_rss,
                   process.concurrency.to_s, process.busy.to_s]
          tui.table_row(cells: cells, style: idx.even? ? nil : Styles::ALT_ROW)
        end
        Table::View[table, tui, title: 'Processes',
                                        header: ['☑️', 'Name', 'Started', 'RSS', 'Threads', 'Busy'],
                                        widths: [tui.constraint_length(5), tui.constraint_fill(1), tui.constraint_length(24),
                                                 tui.constraint_length(10), tui.constraint_length(6), tui.constraint_length(6)],
                                        rows: rows, loading: model.loading]
      }
    end
  end
end
