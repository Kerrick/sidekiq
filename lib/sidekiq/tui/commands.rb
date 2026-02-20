# frozen_string_literal: true

require "sidekiq/api"
require "sidekiq/paginator"

module Sidekiq
  module TUI
    # Fetches shared Sidekiq stats — dispatched on every refresh for all tabs.
    class FetchStats < Data.define
      include Rooibos::Command::Custom

      def call(out, _token)
        raw = Sidekiq::Stats.new
        stats = Stats.new(
          processed: raw.processed, failed: raw.failed, busy: raw.workers_size,
          enqueued: raw.enqueued, retries: raw.retry_size,
          scheduled: raw.scheduled_size, dead: raw.dead_size
        )
        redis_url = Sidekiq.redis { |conn| conn.config.server_url } rescue "N/A"
        out.put(Ractor.make_shareable(StatsFetched.new(stats:, redis_url:)))
      rescue => error
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: error.message, backtrace: error.backtrace&.first(10))))
      end
    end

    # Fetches Redis server info — consumed by HomeTab.
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

    # Fetches process list — consumed by BusyTab.
    class FetchProcesses < Data.define
      include Rooibos::Command::Custom

      def call(out, _token)
        processes = []
        Sidekiq::ProcessSet.new.each do |process|
          processes << ProcessData.new(
            hostname: process["hostname"], pid: process["pid"],
            started_at: Time.at(process["started_at"]).utc,
            rss_kb: process["rss"].to_i, concurrency: process["concurrency"].to_i,
            busy: process["busy"].to_i, identity: process.identity,
            leader: process.leader?, stopping: process.stopping?
          )
        end
        work_set_size = Sidekiq::WorkSet.new.size
        out.put(Ractor.make_shareable(ProcessesFetched.new(processes:, work_set_size:)))
      rescue => error
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: error.message, backtrace: error.backtrace&.first(10))))
      end
    end

    # Fetches queue list — consumed by QueuesTab.
    class FetchQueues < Data.define
      include Rooibos::Command::Custom

      def call(out, _token)
        queue_summaries = Sidekiq::Stats.new.queue_summaries.sort_by(&:name)
        pro = Sidekiq.pro?
        queues = queue_summaries.map { |qs|
          QueueData.new(name: qs.name, size: qs.size, latency: qs.latency.round(2), paused: pro && qs.paused?)
        }
        out.put(Ractor.make_shareable(QueuesFetched.new(queues:, pro:)))
      rescue => error
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: error.message, backtrace: error.backtrace&.first(10))))
      end
    end

    # Shared fetch logic for sorted set commands.
    module FetchSetLogic
      include Sidekiq::Paginator

      def fetch_set(out, set_class, message_class)
        set = set_class.new
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

        out.put(Ractor.make_shareable(message_class.new(
          rows:, row_ids: rows.map { |row| row[:id] },
          current_page: current, total:, next_page: next_pg,
          pager_page: pager_data[:page], pager_size: pager_data[:size]
        )))
      rescue => error
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: error.message, backtrace: error.backtrace&.first(10))))
      end
    end

    class FetchScheduledSet < Data.define(:filter, :pager_page, :pager_size)
      include Rooibos::Command::Custom
      include FetchSetLogic
      def call(out, _token) = fetch_set(out, Sidekiq::ScheduledSet, ScheduledFetched)
    end

    class FetchRetrySet < Data.define(:filter, :pager_page, :pager_size)
      include Rooibos::Command::Custom
      include FetchSetLogic
      def call(out, _token) = fetch_set(out, Sidekiq::RetrySet, RetriesFetched)
    end

    class FetchDeadSet < Data.define(:filter, :pager_page, :pager_size)
      include Rooibos::Command::Custom
      include FetchSetLogic
      def call(out, _token) = fetch_set(out, Sidekiq::DeadSet, DeadFetched)
    end

    # Fetches job metrics time series — consumed by MetricsTab.
    class FetchJobMetrics < Data.define
      include Rooibos::Command::Custom

      def call(out, _token)
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

        out.put(Ractor.make_shareable(MetricsFetched.new(
          datasets:,
          starts_at: query_result.starts_at.iso8601[11..15],
          ends_at: query_result.ends_at.iso8601[11..15]
        )))
      rescue => error
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: error.message, backtrace: error.backtrace&.first(10))))
      end
    end

    # Destructive action commands — these produce ActionComplete.

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

    class ClearQueue < Data.define(:queue_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        Sidekiq::Queue.new(queue_name).clear
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: :clear)))
      end
    end

    class TogglePauseQueue < Data.define(:queue_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        queue = Sidekiq::Queue.new(queue_name)
        queue.paused? ? queue.unpause! : queue.pause!
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: :toggle_pause)))
      end
    end

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
