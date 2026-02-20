# frozen_string_literal: true

module Sidekiq
  module TUI
    class TogglePauseQueue < Data.define(:queue_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        queue = Sidekiq::Queue.new(queue_name)
        queue.paused? ? queue.unpause! : queue.pause!
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: :toggle_pause)))
      end
    end
  end
end
