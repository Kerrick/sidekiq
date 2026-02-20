# frozen_string_literal: true

module Sidekiq
  module TUI
    # Value objects — domain data structures shared across the application.

    class Stats < Data.define(:processed, :failed, :busy, :enqueued, :retries, :scheduled, :dead); end
    class RedisInfo < Data.define(:version, :uptime_days, :connected_clients, :used_memory, :peak_memory); end

    class TableState < Data.define(:rows, :row_ids, :selected, :selected_row_index)
      def selected?(id) = selected.include?(id)
      def action_ids = selected.empty? ? (row_ids.empty? ? [] : [row_ids[selected_row_index]]) : selected
    end

    class PagerState < Data.define(:page, :size, :current_page, :total, :next_page); end

    # Raw process data returned by Commands — formatting happens in the View.
    class ProcessData < Data.define(:hostname, :pid, :started_at, :rss_kb, :concurrency, :busy, :identity, :leader, :stopping); end

    # Raw queue data returned by Commands.
    class QueueData < Data.define(:name, :size, :latency, :paused); end

    EMPTY_TABLE = Ractor.make_shareable(
      TableState.new(rows: [], row_ids: [], selected: [], selected_row_index: 0)
    )
    EMPTY_PAGER = Ractor.make_shareable(
      PagerState.new(page: 1, size: 25, current_page: 1, total: 0, next_page: nil)
    )
    EMPTY_STATS = Ractor.make_shareable(
      Stats.new(processed: 0, failed: 0, busy: 0, enqueued: 0, retries: 0, scheduled: 0, dead: 0)
    )
    EMPTY_REDIS_INFO = Ractor.make_shareable(
      RedisInfo.new(version: "N/A", uptime_days: "N/A", connected_clients: "N/A",
                    used_memory: "N/A", peak_memory: "N/A")
    )
  end
end
