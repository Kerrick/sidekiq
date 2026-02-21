# frozen_string_literal: true

module Sidekiq
  module TUI
    class StatsFetched < Data.define(:stats, :redis_url)
      include Rooibos::Message::Predicates
    end

    class FetchStats < Data.define
      include Rooibos::Command::Custom

      def call(out, _token)
        raw = Sidekiq::Stats.new
        stats = Stats.new(
          processed: raw.processed, failed: raw.failed, busy: raw.workers_size,
          enqueued: raw.enqueued, retries: raw.retry_size,
          scheduled: raw.scheduled_size, dead: raw.dead_size
        )
        redis_url = begin
          Sidekiq.redis { |conn| conn.config.server_url }
        rescue StandardError
          'N/A'
        end
        out.put(Ractor.make_shareable(StatsFetched.new(stats:, redis_url:)))
      rescue StandardError => e
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: e.message,
                                                         backtrace: e.backtrace&.first(10))))
      end
    end
  end
end
