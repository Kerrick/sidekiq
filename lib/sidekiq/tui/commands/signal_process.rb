# frozen_string_literal: true

module Sidekiq
  module TUI
    class SignalProcess < Data.define(:identity, :signal, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        process = Sidekiq::Process.new('identity' => identity)
        case signal
        when :quiet then process.quiet!
        when :terminate then process.stop!
        end
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: signal)))
      end
    end
  end
end
