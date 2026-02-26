# frozen_string_literal: true

module Sidekiq
  module TUI
    module RedisInfo
      class Record < Data.define(:version, :uptime_days, :connected_clients, :used_memory, :peak_memory)
        def uptime_display = (uptime_days == "N/A") ? "N/A" : "#{uptime_days} days"

        EMPTY = Ractor.make_shareable(
          new(version: "N/A", uptime_days: "N/A", connected_clients: "N/A",
            used_memory: "N/A", peak_memory: "N/A")
        )
      end

      class Fetched < Data.define(:redis_info)
        include Rooibos::Message::Predicates
      end

      class Fetch < Data.define
        include Rooibos::Command::Custom

        def call(out, _token)
          redis_info_raw = Sidekiq.default_configuration.redis_info
          redis_info = Record.new(
            version: redis_info_raw["redis_version"] || "N/A",
            uptime_days: redis_info_raw["uptime_in_days"] || "N/A",
            connected_clients: redis_info_raw["connected_clients"] || "N/A",
            used_memory: redis_info_raw["used_memory_human"] || "N/A",
            peak_memory: redis_info_raw["used_memory_peak_human"] || "N/A"
          )
          out.put(Ractor.make_shareable(Fetched.new(redis_info:)))
        rescue => e
          out.put(Ractor.make_shareable(DataFetchError.new(error_message: e.message,
            backtrace: e.backtrace&.first(10))))
        end
      end
    end
  end
end
