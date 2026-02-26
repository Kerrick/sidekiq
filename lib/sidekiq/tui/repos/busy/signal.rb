# frozen_string_literal: true

module Sidekiq
  module TUI
    module Busy
      class Signaled < Data.define(:succeeded_ids)
        include Rooibos::Message::Predicates
      end

      class Signal < Data.define(:identities, :signal, :tab)
        include Rooibos::Command::Custom

        def call(out, _token)
          succeeded_ids = []
          identities.each do |identity|
            process = Sidekiq::Process.new("identity" => identity)
            case signal
            when :quiet then process.quiet!
            when :terminate then process.stop!
            end
            succeeded_ids << identity
          rescue => e
            DebugLogger.info("Busy::Signal: failed on #{identity}: #{e.message}")
            break
          end
          out.put(Ractor.make_shareable(Signaled.new(succeeded_ids:)))
        end
      end
    end
  end
end
