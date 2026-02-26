# frozen_string_literal: true

module Sidekiq
  module TUI
    module Stats
      class Record < Data.define(:processed, :failed, :busy, :enqueued, :retries, :scheduled, :dead)
        EMPTY = Ractor.make_shareable(
          new(processed: 0, failed: 0, busy: 0, enqueued: 0, retries: 0, scheduled: 0, dead: 0)
        )
      end

      class Fetched < Data.define(:stats, :redis_url)
        include Rooibos::Message::Predicates
      end

      class Fetch < Data.define
        include Rooibos::Command::Custom

        def call(out, _token)
          raw = Sidekiq::Stats.new
          stats = Record.new(
            processed: raw.processed, failed: raw.failed, busy: raw.workers_size,
            enqueued: raw.enqueued, retries: raw.retry_size,
            scheduled: raw.scheduled_size, dead: raw.dead_size
          )
          redis_url = begin
            Sidekiq.redis { |conn| conn.config.server_url }
          rescue
            "N/A"
          end
          out.put(Ractor.make_shareable(Fetched.new(stats:, redis_url:)))
        rescue => e
          out.put(Ractor.make_shareable(DataFetchError.new(error_message: e.message,
            backtrace: e.backtrace&.first(10))))
        end
      end
    end
  end
end
