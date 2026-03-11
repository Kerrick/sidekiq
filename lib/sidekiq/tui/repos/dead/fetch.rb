# frozen_string_literal: true

module Sidekiq
  module TUI
    module Dead
      class Record < Data.define(:id, :at, :queue, :display_class, :display_args)
      end

      class Fetched < Data.define(:rows, :row_ids, :current_page, :total, :next_page, :pager_page, :pager_size)
        include Rooibos::Message::Predicates
      end

      class Fetch < Data.define(:filter, :pager_page, :pager_size)
        include FetchSortedSet

        def call(out, _token) = fetch_sorted_set(out, Sidekiq::DeadSet, Fetched, Record)
      end
    end
  end
end
