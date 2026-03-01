# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared messages produced by repos.

    class DataFetchError < Data.define(:error_message, :backtrace)
      include Rooibos::Message::Predicates
    end
  end
end

require_relative "repos/stats/fetch"
require_relative "repos/redis_info/fetch"
require_relative "repos/busy/fetch"
require_relative "repos/busy/signal"
require_relative "repos/queues/fetch"
require_relative "repos/queues/clear"
require_relative "repos/queues/toggle_pause"
require_relative "repos/fetch_set"
require_relative "repos/scheduled/fetch"
require_relative "repos/retry/fetch"
require_relative "repos/dead/fetch"
require_relative "repos/metrics/fetch"
require_relative "repos/set_rows/alter"
