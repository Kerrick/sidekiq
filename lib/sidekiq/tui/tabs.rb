# frozen_string_literal: true

module Sidekiq
  module TUI
    TAB_ORDER = %i[home busy queues scheduled retries dead metrics].freeze
    TAB_NAMES = {
      home: "Home",
      busy: "Busy",
      queues: "Queues",
      scheduled: "Scheduled",
      retries: "Retries",
      dead: "Dead",
      metrics: "Metrics"
    }.freeze

    SET_TABS = %i[scheduled retries dead].freeze

    SET_CLASS_NAMES = {
      scheduled: "Sidekiq::ScheduledSet",
      retries: "Sidekiq::RetrySet",
      dead: "Sidekiq::DeadSet"
    }.freeze
  end
end
