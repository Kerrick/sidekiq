# frozen_string_literal: true

module Sidekiq
  module TUI
    module Queues
      class Cleared < Data.define(:succeeded_ids)
        include Rooibos::Message::Predicates
      end

      class Clear < Data.define(:queue_names, :tab)
        include Rooibos::Command::Custom

        def call(out, _token)
          succeeded_ids = []
          queue_names.each do |queue_name|
            Sidekiq::Queue.new(queue_name).clear
            succeeded_ids << queue_name
          rescue => e
            DebugLogger.info("Queues::Clear: failed on #{queue_name}: #{e.message}")
            break
          end
          out.put(Ractor.make_shareable(Cleared.new(succeeded_ids:)))
        end
      end
    end
  end
end
