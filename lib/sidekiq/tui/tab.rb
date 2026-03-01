# frozen_string_literal: true

module Sidekiq
  module TUI
    module Tab
      def self.included(base)
        base.include Rooibos::Router
        base.extend ClassMethods
      end

      module ClassMethods
        def has_table
          route :table, to: Table
          otherwise route_to: :table
        end
      end
    end
  end
end
