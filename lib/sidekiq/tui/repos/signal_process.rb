# frozen_string_literal: true

module Sidekiq
  module TUI
    class ProcessSignaled < Data.define(:succeeded_ids)
      include Rooibos::Message::Predicates
    end

    class SignalProcess < Data.define(:identities, :signal, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        succeeded_ids = []
        identities.each do |identity|
          process = Sidekiq::Process.new('identity' => identity)
          case signal
          when :quiet then process.quiet!
          when :terminate then process.stop!
          end
          succeeded_ids << identity
        rescue StandardError => e
          DebugLogger.info("SignalProcess: failed on #{identity}: #{e.message}")
          break
        end
        out.put(Ractor.make_shareable(ProcessSignaled.new(succeeded_ids:)))
      end
    end
  end
end
