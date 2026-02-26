# frozen_string_literal: true

module Sidekiq
  module TUI
    module Retry
      include Tab::Set
      entry_methods delete: :delete, retry: :retry, kill: :kill

      map :delete,       :shift_D, 'Delete',    'Delete selected entries'
      map :retry,        :shift_R, 'Retry',     'Retry selected entries'
      map :kill,         :shift_K, 'Kill',      'Kill selected entries'
      map :start_filter, "/",      'Filter',    'Filter entries'

      Model  = from_set
      Init   = set_init
      View   = set_view
      Update = from_router
    end
  end
end
