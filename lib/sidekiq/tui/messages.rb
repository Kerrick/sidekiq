# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared messages produced by multiple commands.

    ActionComplete = Data.define(:tab, :action) do
      include Rooibos::Message::Predicates
    end

    DataFetchError = Data.define(:error_message, :backtrace) do
      include Rooibos::Message::Predicates
    end
  end
end
