# frozen_string_literal: true

module Sidekiq
  module TUI
    module Queues
      # Immutable record of queue data — formatting happens in the View.
      class Record < Data.define(:name, :size, :latency, :paused); end

      class Fetched < Data.define(:queues, :pro)
        include Rooibos::Message::Predicates
      end

      class Fetch < Data.define
        include Rooibos::Command::Custom

        def self.from_model(_model) = [new]

        def call(out, _token)
          queue_summaries = Sidekiq::Stats.new.queue_summaries.sort_by(&:name)
          pro = Sidekiq.pro?
          queues = queue_summaries.map do |qs|
            Record.new(name: qs.name, size: qs.size, latency: qs.latency.round(2), paused: pro && qs.paused?)
          end
          out.put(Ractor.make_shareable(Fetched.new(queues:, pro:)))
        rescue => e
          out.put(Ractor.make_shareable(DataFetchError.new(error_message: e.message,
            backtrace: e.backtrace&.first(10))))
        end
      end
    end
  end
end
