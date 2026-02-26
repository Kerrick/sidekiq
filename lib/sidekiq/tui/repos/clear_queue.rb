# frozen_string_literal: true

module Sidekiq
  module TUI
    class QueueCleared < Data.define(:succeeded_ids)
      include Rooibos::Message::Predicates
    end

    class ClearQueue < Data.define(:queue_names, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        succeeded_ids = []
        queue_names.each do |queue_name|
          Sidekiq::Queue.new(queue_name).clear
          succeeded_ids << queue_name
        rescue StandardError => e
          DebugLogger.info("ClearQueue: failed on #{queue_name}: #{e.message}")
          break
        end
        out.put(Ractor.make_shareable(QueueCleared.new(succeeded_ids:)))
      end
    end
  end
end
