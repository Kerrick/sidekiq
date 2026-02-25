# frozen_string_literal: true

module Sidekiq
  module TUI
    module Retry
      class Fetched < Data.define(:rows, :row_ids, :current_page, :total, :next_page, :pager_page, :pager_size)
        include Rooibos::Message::Predicates
      end

      class Fetch < FetchSet
        def call(out, _token) = fetch_set(out, Sidekiq::RetrySet, Fetched)
      end
    end
  end
end
