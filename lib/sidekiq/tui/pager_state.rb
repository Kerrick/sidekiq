# frozen_string_literal: true

module Sidekiq
  module TUI
    class PagerState < Data.define(:page, :size, :current_page, :total, :next_page)
      def has_prev? = page > 1
      def has_next? = !next_page.nil?

      EMPTY = Ractor.make_shareable(
        new(page: 1, size: 25, current_page: 1, total: 0, next_page: nil)
      )
    end
  end
end
