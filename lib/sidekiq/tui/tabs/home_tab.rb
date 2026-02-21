# frozen_string_literal: true

module Sidekiq
  module TUI
    module HomeTab
      Controls = [].freeze
      FetchCommand = ->(_model) { [FetchRedisInfo.new] }
      Model = Data.define(
        :chart_deltas_processed, :chart_deltas_failed,
        :previous_processed, :previous_failed, :redis_info
      )

      Init = lambda {
        Ractor.make_shareable Model.new(
          chart_deltas_processed: Array.new(50, 0),
          chart_deltas_failed: Array.new(50, 0),
          previous_processed: 0, previous_failed: 0,
          redis_info: EMPTY_REDIS_INFO
        )
      }

      View = lambda { |model, tui, stats: EMPTY_STATS|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_fill(1), tui.constraint_length(4)],
          children: [Views::RenderStats[stats, tui], RenderChart[model, tui], RenderRedis[model.redis_info, tui]]
        )
      }

      Update = lambda { |message, model|
        case message
        in StatsFetched
          pd = message.stats.processed - model.previous_processed
          fd = message.stats.failed - model.previous_failed
          model.with(
            chart_deltas_processed: model.chart_deltas_processed[1..] + [pd],
            chart_deltas_failed: model.chart_deltas_failed[1..] + [fd],
            previous_processed: message.stats.processed,
            previous_failed: message.stats.failed
          )
        in RedisInfoFetched
          model.with(redis_info: message.redis_info)
        else
          model
        end
      }

      RenderChart = lambda { |model, tui|
        y_max = [[model.chart_deltas_processed.max || 0, model.chart_deltas_failed.max || 0].max, 5].max
        proc_data = model.chart_deltas_processed.each_with_index.map { |v, i| [i.to_f, v.to_f] }
        fail_data = model.chart_deltas_failed.each_with_index.map { |v, i| [i.to_f, v.to_f] }
        beacon = Time.now.to_i.even? ? '●' : ' '
        tui.chart(
          datasets: [
            tui.dataset(name: '', data: proc_data, style: tui.style(fg: :green), marker: :dot, graph_type: :line),
            tui.dataset(name: '', data: fail_data, style: tui.style(fg: :red), marker: :dot, graph_type: :line)
          ],
          x_axis: tui.axis(bounds: [0.0, 49.0], labels: [], style: tui.style(fg: :white)),
          y_axis: tui.axis(bounds: [0.0, y_max.to_f],
                           labels: (0...5).map { |i| ((y_max * i) / 4).round.to_s },
                           style: tui.style(fg: :white)),
          block: tui.block(title: "Dashboard #{beacon}", borders: [:all])
        )
      }

      RenderRedis = lambda { |redis_info, tui|
        uptime = redis_info.uptime_days == 'N/A' ? 'N/A' : "#{redis_info.uptime_days} days"
        keys = ['Version', 'Uptime', 'Connected Clients', 'Memory Usage', 'Peak Memory']
        vals = [redis_info.version, uptime, redis_info.connected_clients,
                redis_info.used_memory, redis_info.peak_memory]
        tui.paragraph(
          text: [keys.map { |k| k.ljust(18) }.join('  '), vals.map { |v| v.to_s.ljust(18) }.join('  ')],
          block: tui.block(title: 'Redis Information', borders: [:all])
        )
      }
    end
  end
end
