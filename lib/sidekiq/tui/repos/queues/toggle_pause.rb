# frozen_string_literal: true

module Sidekiq
  module TUI
    module Queues
      class PauseToggled < Data.define(:succeeded_ids)
        include Rooibos::Message::Predicates
      end

      class TogglePause < Data.define(:queue_names, :tab)
        include Rooibos::Command::Custom

        def call(out, _token)
          return unless Sidekiq.pro?

          succeeded_ids = []
          queue_names.each do |queue_name|
            queue = Sidekiq::Queue.new(queue_name)
            queue.paused? ? queue.unpause! : queue.pause!
            succeeded_ids << queue_name
          end
          out.put(Ractor.make_shareable(PauseToggled.new(succeeded_ids:)))
        end
      end
    end
  end
end
