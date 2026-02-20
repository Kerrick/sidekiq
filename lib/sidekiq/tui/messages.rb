# frozen_string_literal: true

module Sidekiq
  module TUI
    # Custom messages — each Command produces a specific message type.
    # The type itself routes the message to the correct fragment.

    StatsFetched = Data.define(:stats, :redis_url) do
      include Rooibos::Message::Predicates
    end

    RedisInfoFetched = Data.define(:redis_info) do
      include Rooibos::Message::Predicates
    end

    ProcessesFetched = Data.define(:processes, :work_set_size) do
      include Rooibos::Message::Predicates
    end

    QueuesFetched = Data.define(:queues, :pro) do
      include Rooibos::Message::Predicates
    end

    ScheduledFetched = Data.define(:rows, :row_ids, :current_page, :total, :next_page, :pager_page, :pager_size) do
      include Rooibos::Message::Predicates
    end

    RetriesFetched = Data.define(:rows, :row_ids, :current_page, :total, :next_page, :pager_page, :pager_size) do
      include Rooibos::Message::Predicates
    end

    DeadFetched = Data.define(:rows, :row_ids, :current_page, :total, :next_page, :pager_page, :pager_size) do
      include Rooibos::Message::Predicates
    end

    MetricsFetched = Data.define(:datasets, :starts_at, :ends_at) do
      include Rooibos::Message::Predicates
    end

    ActionComplete = Data.define(:tab, :action) do
      include Rooibos::Message::Predicates
    end

    DataFetchError = Data.define(:error_message, :backtrace) do
      include Rooibos::Message::Predicates
    end
  end
end
