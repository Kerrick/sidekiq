# frozen_string_literal: true

module Sidekiq
  module TUI
    module Home
      include Tab

      Model = Data.define(
        :loading, :beacon_on, :chart_deltas_processed, :chart_deltas_failed,
        :previous_processed, :previous_failed, :redis_info
      )

      module Fetch
        def self.from_model(_model) = RedisInfo::Fetch.new
      end

      Init = lambda {
        model = Ractor.make_shareable Model.new(
          loading: true, beacon_on: true,
          chart_deltas_processed: Array.new(50, 0),
          chart_deltas_failed: Array.new(50, 0),
          previous_processed: 0, previous_failed: 0,
          redis_info: RedisInfo::Record::EMPTY
        )
        [model, RedisInfo::Fetch.new]
      }

      View = lambda { |model, tui|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_fill(1), tui.constraint_length(4)],
          children: [ChartView[model, tui], RedisView[model, tui]]
        )
      }

      receive_instances_of Stats::Fetched, lambda { |message, model|
        pd = message.stats.processed - model.previous_processed
        fd = message.stats.failed - model.previous_failed
        model.with(
          chart_deltas_processed: model.chart_deltas_processed[1..] + [pd],
          chart_deltas_failed: model.chart_deltas_failed[1..] + [fd],
          previous_processed: message.stats.processed,
          previous_failed: message.stats.failed
        )
      }

      receive_instances_of RedisInfo::Fetched, lambda { |message, model|
        model.with(loading: false, redis_info: message.redis_info)
      }

      receive_routed :clock, ->(_, model) { model.with(beacon_on: !model.beacon_on) }

      Update = from_router

      ChartView = lambda { |model, tui|
        y_max = [[model.chart_deltas_processed.max || 0, model.chart_deltas_failed.max || 0].max, 5].max
        proc_data = model.chart_deltas_processed.each_with_index.map { |v, i| [i.to_f, v.to_f] }
        fail_data = model.chart_deltas_failed.each_with_index.map { |v, i| [i.to_f, v.to_f] }
        beacon = model.beacon_on ? "●" : " "
        tui.chart(
          datasets: [
            tui.dataset(name: "", data: proc_data, style: tui.style(fg: :green), marker: :dot, graph_type: :line),
            tui.dataset(name: "", data: fail_data, style: tui.style(fg: :red), marker: :dot, graph_type: :line)
          ],
          x_axis: tui.axis(bounds: [0.0, 49.0], labels: [], style: tui.style(fg: :white)),
          y_axis: tui.axis(bounds: [0.0, y_max.to_f],
            labels: (0...5).map { |i| ((y_max * i) / 4).round.to_s },
            style: tui.style(fg: :white)),
          block: tui.block(title: "Dashboard #{beacon}", borders: [:all])
        )
      }

      RedisView = lambda { |model, tui|
        keys = ["Version", "Uptime", "Connected Clients", "Memory Usage", "Peak Memory"]
        vals = if model.loading
          Array.new(5, "…")
        else
          [model.redis_info.version, model.redis_info.uptime_display, model.redis_info.connected_clients,
            model.redis_info.used_memory, model.redis_info.peak_memory]
        end
        tui.paragraph(
          text: [keys.map { |k| k.ljust(18) }.join("  "), vals.map { |v| v.to_s.ljust(18) }.join("  ")],
          block: tui.block(title: "Redis Information", borders: [:all])
        )
      }
    end
  end
end
