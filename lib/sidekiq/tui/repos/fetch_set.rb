# frozen_string_literal: true

require "sidekiq/paginator"

module Sidekiq
  module TUI
    # Base class for sorted-set fetch commands. Subclasses need only
    # define `call` to specify their Sidekiq set class and Fetched class.
    class FetchSet < Data.define(:filter, :pager_page, :pager_size)
      include Rooibos::Command::Custom
      include Sidekiq::Paginator

      def self.from_model(model)
        [new(filter: model.set.filter_model.text, pager_page: model.set.pager.page,
          pager_size: model.set.pager.size)]
      end

      private

      def fetch_set(out, set_class, message_class)
        set = set_class.new
        current_filter = filter

        pager_data, rows_data, current, total =
          if current_filter && current_filter.size > 2
            scan_rows = set.scan(current_filter).to_a
            size = scan_rows.size
            [{page: 1, size: size}, scan_rows, 1, size]
          else
            page_num = pager_page || 1
            page_size = pager_size || 25
            current_pg, total_count, items = page(set.name, page_num, page_size)
            item_rows = items.map { |message, score| Sidekiq::SortedEntry.new(nil, score, message) }
            [{page: page_num, size: page_size}, item_rows, current_pg, total_count]
          end

        rows = rows_data.map do |entry|
          {id: [entry.score, entry["jid"]].join("|"),
           at: entry.at.to_s, queue: entry.queue.to_s,
           display_class: entry.display_class.to_s, display_args: entry.display_args.to_s}
        end

        next_pg = (current * pager_data[:size] < total) ? pager_data[:page] + 1 : nil

        out.put(Ractor.make_shareable(message_class.new(
          rows:, row_ids: rows.map { |row| row[:id] },
          current_page: current, total:, next_page: next_pg,
          pager_page: pager_data[:page], pager_size: pager_data[:size]
        )))
      rescue => e
        out.put(Ractor.make_shareable(DataFetchError.new(error_message: e.message,
          backtrace: e.backtrace&.first(10))))
      end
    end
  end
end
