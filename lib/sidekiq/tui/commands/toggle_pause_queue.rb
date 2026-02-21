# frozen_string_literal: true

module Sidekiq
  module TUI
    class TogglePauseQueue < Data.define(:queue_names, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        return unless Sidekiq.pro?

        succeeded_ids = []
        queue_names.each do |queue_name|
          queue = Sidekiq::Queue.new(queue_name)
          queue.paused? ? queue.unpause! : queue.pause!
          succeeded_ids << queue_name
        rescue StandardError => e
          DebugLogger.info("TogglePauseQueue: failed on #{queue_name}: #{e.message}")
          break
        end
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: :toggle_pause, succeeded_ids:)))
      end
    end
  end
end
