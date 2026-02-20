# frozen_string_literal: true

module Sidekiq
  module TUI
    class RedisInfoFetched < Data.define(:redis_info)
      include Rooibos::Message::Predicates
    end

    class FetchRedisInfo < Data.define
      include Rooibos::Command::Custom

      def call(out, _token)
        redis_info_raw = Sidekiq.default_configuration.redis_info
        redis_info = RedisInfo.new(
          version: redis_info_raw["redis_version"] || "N/A",
          uptime_days: redis_info_raw["uptime_in_days"] || "N/A",
          connected_clients: redis_info_raw["connected_clients"] || "N/A",
          used_memory: redis_info_raw["used_memory_human"] || "N/A",
          peak_memory: redis_info_raw["used_memory_peak_human"] || "N/A"
        )
        out.put(Ractor.make_shareable(RedisInfoFetched.new(redis_info:)))
      rescue => error
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: error.message, backtrace: error.backtrace&.first(10))))
      end
    end
  end
end
