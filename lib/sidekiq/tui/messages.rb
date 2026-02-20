# frozen_string_literal: true

module Sidekiq
  module TUI
    # Result of an async data fetch for a tab.
    DataFetched = Data.define(:tab, :stats, :tab_data, :redis_url)

    # Result of an async destructive action (delete, retry, etc.)
    ActionComplete = Data.define(:tab, :action)

    # Result of an async data fetch that failed.
    DataFetchError = Data.define(:tab, :error_message, :backtrace)
  end
end
