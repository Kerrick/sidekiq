# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared messages produced by repos — action completions and fetch errors.

    class ActionComplete < Data.define(:tab, :action, :succeeded_ids)
      include Rooibos::Message::Predicates
    end

    class DataFetchError < Data.define(:error_message, :backtrace)
      include Rooibos::Message::Predicates
    end
  end
end

require_relative 'repos/stats'
require_relative 'repos/redis_info'
require_relative 'repos/processes'
require_relative 'repos/queues'
require_relative 'repos/fetch_set'
require_relative 'repos/fetch_job_metrics'
require_relative 'repos/alter_set_rows'
require_relative 'repos/clear_queue'
require_relative 'repos/toggle_pause_queue'
require_relative 'repos/signal_process'
