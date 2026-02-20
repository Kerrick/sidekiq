# frozen_string_literal: true

require "sidekiq/api"
require "sidekiq/paginator"

module Sidekiq
  module TUI
    # Shared stats fetching for all tab commands.
    module FetchStats
      def fetch_stats
        stats = Sidekiq::Stats.new
        {
          processed: stats.processed,
          failed: stats.failed,
          busy: stats.workers_size,
          enqueued: stats.enqueued,
          retries: stats.retry_size,
          scheduled: stats.scheduled_size,
          dead: stats.dead_size
        }.freeze
      end

      def fetch_redis_url
        Sidekiq.redis { |conn| conn.config.server_url }.freeze
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

      def emit(out, tab, stats, tab_data, redis_url)
        result = DataFetched.new(tab:, stats:, tab_data:, redis_url:)
        out.put(Ractor.make_shareable(result))
      rescue => e
        result = DataFetchError.new(
          tab:,
          error_message: e.message.freeze,
          backtrace: e.backtrace&.first(10)&.map(&:freeze)&.freeze
        )
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
          processed: stats[:processed],
          failed: stats[:failed],
          redis_info: {
            version: (redis_info_raw["redis_version"] || "N/A").freeze,
            uptime_days: (redis_info_raw["uptime_in_days"] || "N/A").freeze,
            connected_clients: (redis_info_raw["connected_clients"] || "N/A").freeze,
            used_memory: (redis_info_raw["used_memory_human"] || "N/A").freeze,
            peak_memory: (redis_info_raw["used_memory_peak_human"] || "N/A").freeze
          }.freeze
        }.freeze
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

        Sidekiq::ProcessSet.new.each do |p|
          name = "#{p["hostname"]}:#{p["pid"]}"
          name += " ⭐️" if p.leader?
          name += " 🛑" if p.stopping?
          processes << [
            name.freeze,
            Time.at(p["started_at"]).utc.to_s.freeze,
            format_memory(p["rss"].to_i).freeze,
            p["concurrency"].to_s.freeze,
            p["busy"].to_s.freeze
          ].freeze
          row_ids << p.identity.freeze
          total_concurrency += p["concurrency"].to_i
          total_rss += p["rss"].to_i
          process_count += 1
        end

        ws = Sidekiq::WorkSet.new.size
        utilization = (total_concurrency == 0) ? "0%" : "#{((ws / total_concurrency.to_f) * 100).round(0)}%"

        tab_data = {
          rows: processes.freeze,
          row_ids: row_ids.freeze,
          status: {
            processes: process_count.to_s.freeze,
            threads: total_concurrency.to_s.freeze,
            busy: ws.to_s.freeze,
            utilization: utilization.freeze,
            rss: format_memory(total_rss).freeze
          }.freeze
        }.freeze
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
          cells = [
            qs.name.freeze,
            qs.size.to_s.freeze,
            qs.latency.round(2).to_s.freeze
          ]
          cells << (qs.paused? ? "✅" : "").freeze if pro
          cells.freeze
        }.freeze
        row_ids = queue_summaries.map { |qs| qs.name.freeze }.freeze

        tab_data = { rows:, row_ids:, pro: }.freeze
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
        f = filter

        pager_data, rows_data, current, total =
          if f && f.size > 2
            scan_rows = set.scan(f).to_a
            sz = scan_rows.size
            [{ page: 1, size: sz }, scan_rows, 1, sz]
          else
            pg = pager_page || 1
            sz = pager_size || 25
            current_pg, total_count, items = page(set.name, pg, sz)
            item_rows = items.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
            [{ page: pg, size: sz }, item_rows, current_pg, total_count]
          end

        rows = rows_data.map { |entry|
          {
            id: [entry.score, entry["jid"]].join("|").freeze,
            at: entry.at.to_s.freeze,
            queue: entry.queue.to_s.freeze,
            display_class: entry.display_class.to_s.freeze,
            display_args: entry.display_args.to_s.freeze
          }.freeze
        }.freeze

        next_pg = (current * pager_data[:size] < total) ? pager_data[:page] + 1 : nil

        tab_data = {
          rows:,
          row_ids: rows.map { |r| r[:id] }.freeze,
          current_page: current,
          total:,
          next_page: next_pg,
          pager_page: pager_data[:page],
          pager_size: pager_data[:size]
        }.freeze
        emit(out, tab, stats, tab_data, fetch_redis_url)
      end
    end

    # Fetches Metrics tab data: job execution time series.
    class FetchMetrics < Data.define
      include Rooibos::Command::Custom
      include FetchStats

      def call(out, _token)
        stats = fetch_stats
        q = Sidekiq::Metrics::Query.new
        query_result = q.top_jobs(minutes: 60)
        job_results = query_result.job_results.sort_by { |(_kls, jr)| jr.totals["s"] }.reverse.first(7)

        datasets = job_results.map { |kls, data|
          hrdata = data.dig("series", "s")
          tm = Time.now
          tmi = tm.to_i
          tm = Time.at(tmi - (tmi % 60)).utc
          points = Array.new(60) { |idx|
            jumpback = idx * 60
            value = hrdata[(tm - jumpback).iso8601] || 0
            [59 - idx, value]
          }.freeze
          { name: kls.freeze, data: points }.freeze
        }.freeze

        tab_data = {
          datasets:,
          starts_at: query_result.starts_at.iso8601[11..15].freeze,
          ends_at: query_result.ends_at.iso8601[11..15].freeze
        }.freeze
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
