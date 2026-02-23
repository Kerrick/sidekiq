# frozen_string_literal: true

module Sidekiq
  module TUI
    # Value objects — domain data structures shared across the application.

    class PagerState < Data.define(:page, :size, :current_page, :total, :next_page)
      def has_prev? = page > 1
      def has_next? = !next_page.nil?

      EMPTY = Ractor.make_shareable(
        new(page: 1, size: 25, current_page: 1, total: 0, next_page: nil)
      )
    end

    # Couples a key binding with its semantic name and display label.
    class TabControl < Data.define(:key, :semantic, :display_key, :description); end
  end
end
