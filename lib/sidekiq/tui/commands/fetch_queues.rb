# frozen_string_literal: true

module Sidekiq
  module TUI
    class QueuesFetched < Data.define(:queues, :pro)
      include Rooibos::Message::Predicates
    end

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
  end
end
