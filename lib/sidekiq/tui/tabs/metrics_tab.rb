# frozen_string_literal: true

module Sidekiq
  module TUI
    module MetricsTab
      Controls = [].freeze
      FetchCommand = ->(_model) { [FetchJobMetrics.new] }
      COLORS = %i[blue cyan yellow red green white gray].freeze

      Model = Data.define(:datasets, :starts_at, :ends_at, :metrics_refresh_at)

      Init = lambda {
        Ractor.make_shareable Model.new(datasets: [], starts_at: '', ends_at: '', metrics_refresh_at: nil)
      }

      View = lambda { |model, tui, stats: EMPTY_STATS|
        tui.layout(
          direction: :vertical,
          constraints: [tui.constraint_length(4), tui.constraint_fill(1)],
          children: [Views::RenderStats[stats, tui], RenderChart[model, tui]]
        )
      }

      Update = lambda { |message, model|
        case message
        in MetricsFetched
          model.with(datasets: message.datasets, starts_at: message.starts_at,
                     ends_at: message.ends_at, metrics_refresh_at: Time.now + 60)
        else
          model
        end
      }

      RenderChart = lambda { |model, tui|
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
          block: tui.block(title: 'Metrics', borders: [:all])
        )
      }
    end
  end
end
