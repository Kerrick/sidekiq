# frozen_string_literal: true

module Sidekiq
  module TUI
    module Processes
      # Immutable record of process data — formatting happens in the View.
      class Record < Data.define(:hostname, :pid, :started_at, :rss_kb, :concurrency, :busy, :identity, :leader,
                                 :stopping)
      end

      class Fetched < Data.define(:processes, :work_set_size)
        include Rooibos::Message::Predicates
      end

      class Fetch < Data.define
        include Rooibos::Command::Custom

        def call(out, _token)
          processes = []
          Sidekiq::ProcessSet.new.each do |process|
            processes << Record.new(
              hostname: process['hostname'], pid: process['pid'],
              started_at: Time.at(process['started_at']).utc,
              rss_kb: process['rss'].to_i, concurrency: process['concurrency'].to_i,
              busy: process['busy'].to_i, identity: process.identity,
              leader: process.leader?, stopping: process.stopping?
            )
          end
          work_set_size = Sidekiq::WorkSet.new.size
          out.put(Ractor.make_shareable(Fetched.new(processes:, work_set_size:)))
        rescue StandardError => e
          out.put(Ractor.make_shareable(DataFetchError.new(error_message: e.message,
                                                           backtrace: e.backtrace&.first(10))))
        end
      end
    end
  end
end
