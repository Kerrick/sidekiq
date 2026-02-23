# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared types and constants used across fragments and repos.

    TAB_ORDER = %i[home busy queues scheduled retries dead metrics].freeze
    TAB_NAMES = {
      home: 'Home', busy: 'Busy', queues: 'Queues', scheduled: 'Scheduled',
      retries: 'Retries', dead: 'Dead', metrics: 'Metrics'
    }.freeze
    SET_TABS = %i[scheduled retries dead].freeze
    SET_CLASS_NAMES = {
      scheduled: 'Sidekiq::ScheduledSet', retries: 'Sidekiq::RetrySet', dead: 'Sidekiq::DeadSet'
    }.freeze

    class TabControl < Data.define(:key, :semantic, :display_key, :description); end

    class ActionComplete < Data.define(:tab, :action, :succeeded_ids)
      include Rooibos::Message::Predicates
    end

    class DataFetchError < Data.define(:error_message, :backtrace)
      include Rooibos::Message::Predicates
    end
  end
end
