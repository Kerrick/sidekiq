# frozen_string_literal: true

module Sidekiq
  module TUI
    class ClearQueue < Data.define(:queue_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        Sidekiq::Queue.new(queue_name).clear
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: :clear)))
      end
    end
  end
end
