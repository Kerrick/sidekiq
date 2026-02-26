# frozen_string_literal: true

module Sidekiq
  module TUI
    module Dead
      include Tab::Set

      map :delete, :shift_D, "Delete", "Delete selected entries"
      map :add_to_queue, :shift_E, "Enqueue", "Enqueue selected entries"
      map :start_filter, "/", "Filter", "Filter entries"

      Model = from_set
      Init = set_init
      View = set_view
      Update = from_router
    end
  end
end
