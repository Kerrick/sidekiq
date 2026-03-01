# frozen_string_literal: true

module Sidekiq
  module TUI
    module Retry
      include Tab::Set

      Model = from_set
      Init = set_init
      View = set_view
      Update = from_router
    end
  end
end
