# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared messages produced by multiple commands.

    class ActionComplete < Data.define(:tab, :action)
      include Rooibos::Message::Predicates
    end

    class DataFetchError < Data.define(:error_message, :backtrace)
      include Rooibos::Message::Predicates
    end
  end
end
