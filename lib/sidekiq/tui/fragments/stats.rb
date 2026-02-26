# frozen_string_literal: true

module Sidekiq
  module TUI
    module Stats
      Model = Data.define(:stats, :loading, :redis_url)

      Init = lambda {
        model = Ractor.make_shareable Model.new(
          stats: Record::EMPTY, loading: true, redis_url: "N/A"
        )
        [model, Stats::Fetch.new]
      }

      View = lambda { |model, tui|
        keys = %w[Processed Failed Busy Enqueued Retries Scheduled Dead]
        vals = if model.loading
          Array.new(keys.size, "…")
        else
          keys.map { |k| model.stats.public_send(k.downcase) }
        end
        tui.paragraph(
          text: [keys.map { |k| k.ljust(12) }.join("  "),
            vals.map { |v| v.to_s.ljust(12) }.join("  ")],
          block: tui.block(title: "Statistics", borders: [:all])
        )
      }

      Update = lambda { |message, model|
        case message
        in Stats::Fetched
          model.with(stats: message.stats, loading: false, redis_url: message.redis_url)
        else
          model
        end
      }
    end
  end
end
