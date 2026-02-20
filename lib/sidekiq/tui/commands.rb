# frozen_string_literal: true

require "sidekiq/api"
require "sidekiq/paginator"

module Sidekiq
  module TUI
    # Shared stats fetching for all tab commands.
    module FetchStats
      def fetch_stats
        raw = Sidekiq::Stats.new
        Stats.new(
          processed: raw.processed, failed: raw.failed, busy: raw.workers_size,
          enqueued: raw.enqueued, retries: raw.retry_size,
          scheduled: raw.scheduled_size, dead: raw.dead_size
        )
      end

      def fetch_redis_url
        Sidekiq.redis { |conn| conn.config.server_url }
      rescue
        "N/A"
      end

      def format_memory(rss_kb)
        return "0" if rss_kb.nil? || rss_kb == 0

        if rss_kb < 100_000
          "#{rss_kb} KB"
        elsif rss_kb < 10_000_000
          "#{(rss_kb / 1024.0).to_i} MB"
        else
          "#{(rss_kb / (1024.0 * 1024.0)).round(1)} GB"
        end
      end

      # Single Ractor.make_shareable at the boundary.
      def emit(out, tab, stats, tab_data, redis_url)
        result = DataFetched.new(tab:, stats:, tab_data:, redis_url:)
        out.put(Ractor.make_shareable(result))
      rescue => e
        result = DataFetchError.new(tab:, error_message: e.message, backtrace: e.backtrace&.first(10))
        out.put(Ractor.make_shareable(result))
      end
    end

    # Fetches Home tab data: stats deltas and Redis info.
    class FetchHome < Data.define
      include Rooibos::Command::Custom
      include FetchStats

      def call(out, _token)
        stats = fetch_stats
        redis_info_raw = Sidekiq.default_configuration.redis_info
        tab_data = {
          processed: stats.processed,
          failed: stats.failed,
          redis_info: RedisInfo.new(
            version: redis_info_raw["redis_version"] || "N/A",
            uptime_days: redis_info_raw["uptime_in_days"] || "N/A",
            connected_clients: redis_info_raw["connected_clients"] || "N/A",
            used_memory: redis_info_raw["used_memory_human"] || "N/A",
            peak_memory: redis_info_raw["used_memory_peak_human"] || "N/A"
          )
        }
        emit(out, :home, stats, tab_data, fetch_redis_url)
      end
    end

    # Fetches Busy tab data: process list and utilization status.
    class FetchBusy < Data.define
      include Rooibos::Command::Custom
      include FetchStats

      def call(out, _token)
        stats = fetch_stats
        processes = []
        row_ids = []
        total_concurrency = 0
        total_rss = 0
        process_count = 0

        Sidekiq::ProcessSet.new.each do |process|
          name = "#{process["hostname"]}:#{process["pid"]}"
          name += " ⭐️" if process.leader?
          name += " 🛑" if process.stopping?
          processes << [name, Time.at(process["started_at"]).utc.to_s, format_memory(process["rss"].to_i),
                        process["concurrency"].to_s, process["busy"].to_s]
          row_ids << process.identity
          total_concurrency += process["concurrency"].to_i
          total_rss += process["rss"].to_i
          process_count += 1
        end

        work_set_size = Sidekiq::WorkSet.new.size
        utilization = (total_concurrency == 0) ? "0%" : "#{((work_set_size / total_concurrency.to_f) * 100).round(0)}%"

        tab_data = {
          rows: processes,
          row_ids: row_ids,
          status: BusyStatus.new(
            processes: process_count.to_s, threads: total_concurrency.to_s,
            busy: work_set_size.to_s, utilization: utilization, rss: format_memory(total_rss)
          )
        }
        emit(out, :busy, stats, tab_data, fetch_redis_url)
      end
    end

    # Fetches Queues tab data: queue list with sizes and latencies.
    class FetchQueues < Data.define
      include Rooibos::Command::Custom
      include FetchStats

      def call(out, _token)
        stats = fetch_stats
        queue_summaries = Sidekiq::Stats.new.queue_summaries.sort_by(&:name)
        pro = Sidekiq.pro?
        rows = queue_summaries.map { |qs|
          cells = [qs.name, qs.size.to_s, qs.latency.round(2).to_s]
          cells << (qs.paused? ? "✅" : "") if pro
          cells
        }
        row_ids = queue_summaries.map(&:name)

        tab_data = { rows:, row_ids:, pro: }
        emit(out, :queues, stats, tab_data, fetch_redis_url)
      end
    end

    # Fetches sorted set tab data with pagination and filtering.
    class FetchSet < Data.define(:tab, :set_class_name, :filter, :pager_page, :pager_size)
      include Rooibos::Command::Custom
      include FetchStats
      include Sidekiq::Paginator

      def call(out, _token)
        stats = fetch_stats
        set = Object.const_get(set_class_name).new
        current_filter = filter

        pager_data, rows_data, current, total =
          if current_filter && current_filter.size > 2
            scan_rows = set.scan(current_filter).to_a
            size = scan_rows.size
            [{ page: 1, size: size }, scan_rows, 1, size]
          else
            page_num = pager_page || 1
            page_size = pager_size || 25
            current_pg, total_count, items = page(set.name, page_num, page_size)
            item_rows = items.map { |message, score| Sidekiq::SortedEntry.new(nil, score, message) }
            [{ page: page_num, size: page_size }, item_rows, current_pg, total_count]
          end

        rows = rows_data.map { |entry|
          { id: [entry.score, entry["jid"]].join("|"),
            at: entry.at.to_s, queue: entry.queue.to_s,
            display_class: entry.display_class.to_s, display_args: entry.display_args.to_s }
        }

        next_pg = (current * pager_data[:size] < total) ? pager_data[:page] + 1 : nil

        tab_data = {
          rows:, row_ids: rows.map { |row| row[:id] },
          current_page: current, total:, next_page: next_pg,
          pager_page: pager_data[:page], pager_size: pager_data[:size]
        }
        emit(out, tab, stats, tab_data, fetch_redis_url)
      end
    end

    # Fetches Metrics tab data: job execution time series.
    class FetchMetrics < Data.define
      include Rooibos::Command::Custom
      include FetchStats

      def call(out, _token)
        stats = fetch_stats
        query = Sidekiq::Metrics::Query.new
        query_result = query.top_jobs(minutes: 60)
        job_results = query_result.job_results.sort_by { |(_kls, jr)| jr.totals["s"] }.reverse.first(7)

        datasets = job_results.map { |kls, data|
          hrdata = data.dig("series", "s")
          now = Time.now
          now_i = now.to_i
          rounded = Time.at(now_i - (now_i % 60)).utc
          points = Array.new(60) { |idx|
            jumpback = idx * 60
            value = hrdata[(rounded - jumpback).iso8601] || 0
            [59 - idx, value]
          }
          { name: kls, data: points }
        }

        tab_data = {
          datasets:,
          starts_at: query_result.starts_at.iso8601[11..15],
          ends_at: query_result.ends_at.iso8601[11..15]
        }
        emit(out, :metrics, stats, tab_data, fetch_redis_url)
      end
    end

    # Executes a destructive action on a Sidekiq sorted set.
    class AlterSetRows < Data.define(:set_class_name, :ids, :action_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        set = Object.const_get(set_class_name).new
        ids.each do |id|
          score, jid = id.split("|")
          item = set.fetch(score, jid)&.first
          item&.send(action_name)
        end
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: action_name)))
      end
    end

    # Clears a named queue.
    class ClearQueue < Data.define(:queue_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        Sidekiq::Queue.new(queue_name).clear
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: :clear)))
      end
    end

    # Toggles pause on a queue (Sidekiq Pro only).
    class TogglePauseQueue < Data.define(:queue_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        queue = Sidekiq::Queue.new(queue_name)
        if queue.paused?
          queue.unpause!
        else
          queue.pause!
        end
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: :toggle_pause)))
      end
    end

    # Sends a signal to a Sidekiq process (quiet or terminate).
    class SignalProcess < Data.define(:identity, :signal, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        process = Sidekiq::Process.new("identity" => identity)
        case signal
        when :quiet then process.quiet!
        when :terminate then process.stop!
        end
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: signal)))
      end
    end
  end
end
