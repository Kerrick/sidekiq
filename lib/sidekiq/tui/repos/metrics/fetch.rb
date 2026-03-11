# frozen_string_literal: true

module Sidekiq
  module TUI
    module Metrics
      class Fetched < Data.define(:datasets, :starts_at, :ends_at)
        include Rooibos::Message::Predicates
      end

      class Fetch < Data.define
        include Rooibos::Command::Custom

        def self.from_model(model)
          ticks = model.metrics_ticks_until_refresh
          new if ticks&.<=(0)
        end

        def call(out, _token)
          query = Sidekiq::Metrics::Query.new
          query_result = query.top_jobs(minutes: 60)
          job_results = query_result.job_results.sort_by { |(_kls, jr)| jr.totals["s"] }.last(7).reverse

          datasets = job_results.map do |kls, data|
            hrdata = data.dig("series", "s")
            now = Time.now
            now_i = now.to_i
            rounded = Time.at(now_i - (now_i % 60)).utc
            points = Array.new(60) do |idx|
              jumpback = idx * 60
              value = hrdata[(rounded - jumpback).iso8601] || 0
              [59 - idx, value]
            end
            {name: kls, data: points}
          end

          out.put(Ractor.make_shareable(Fetched.new(
            datasets:,
            starts_at: query_result.starts_at.iso8601[11..15],
            ends_at: query_result.ends_at.iso8601[11..15]
          )))
        rescue => e
          out.put(Ractor.make_shareable(DataFetchError.new(error_message: e.message,
            backtrace: e.backtrace&.first(10))))
        end
      end
    end
  end
end
