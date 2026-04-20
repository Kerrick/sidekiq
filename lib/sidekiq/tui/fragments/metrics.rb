# frozen_string_literal: true

module Sidekiq
  module TUI
    module Metrics
      include Tab

      COLORS = %i[light_blue light_cyan light_yellow light_red light_green white gray].freeze

      Model = Data.define(:loading, :datasets, :starts_at, :ends_at, :metrics_ticks_until_refresh)

      Init = lambda {
        model = Ractor.make_shareable Model.new(loading: true, datasets: [], starts_at: "", ends_at: "", metrics_ticks_until_refresh: nil)
        [model, Metrics::Fetch.new]
      }

      receive_routed :clock, lambda { |_, model|
        return model if model.metrics_ticks_until_refresh.nil?
        model.with(metrics_ticks_until_refresh: model.metrics_ticks_until_refresh - 1)
      }

      View = lambda { |model, tui|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_fill(1)],
          children: [ChartView[model, tui]]
        )
      }

      receive_instances_of Metrics::Fetched, lambda { |message, model|
        model.with(loading: false, datasets: message.datasets, starts_at: message.starts_at,
          ends_at: message.ends_at, metrics_ticks_until_refresh: 60)
      }

      Update = from_router

      ChartView = lambda { |model, tui|
        y_max = 5
        datasets = model.datasets.each_with_index.map do |ds, idx|
          actual_max = ds[:data].map { |_x, y| y }.max || 0
          y_max = actual_max if actual_max > y_max
          tui.dataset(name: ds[:name], data: ds[:data],
            style: tui.style(fg: COLORS[idx % COLORS.size]),
            marker: :dot, graph_type: :line)
        end
        y_labels = (0...5).map { |i| ((y_max * i) / 4).round.to_s }
        tui.chart(
          datasets: datasets,
          x_axis: tui.axis(bounds: [0.0, 60.0], labels: [model.starts_at.to_s, model.ends_at.to_s],
            style: tui.style(fg: :white)),
          y_axis: tui.axis(bounds: [0.0, y_max.to_f], labels: y_labels, style: tui.style(fg: :white)),
          block: tui.block(title: "Metrics", borders: [:all])
        )
      }
    end
  end
end
