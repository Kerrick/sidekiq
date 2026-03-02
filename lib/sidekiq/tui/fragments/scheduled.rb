# frozen_string_literal: true

module Sidekiq
  module TUI
    module Scheduled
      include Tab::SortedSet
      acts_as_sorted_set

      Model = from_sorted_set
      Init = sorted_set_init
      View = sorted_set_view
      Update = from_router
    end
  end
end
