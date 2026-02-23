# frozen_string_literal: true

module Sidekiq
  module TUI
    # App-level mixin for tab fragments. Provides the Router DSL,
    # default empty key bindings, default no-op FetchCommand,
    # and class macros for common tab patterns.
    module Tab
      def self.included(base)
        base.include Rooibos::Router
        base.extend ClassMethods
        base.instance_variable_set(:@key_bindings, [])
      end

      module ClassMethods
        def has_table
          route :table, to: TableFragment
          otherwise route_to: :table
        end

        def has_set
          route :set, to: SetFragment
          otherwise route_to: :set
        end

        def fetch_command(fetch_class)
          const_set(:FetchCommand, ->(_model) { [fetch_class.new] })
        end

        def map(semantic, key, description)
          display_key = key.to_s.delete_prefix('shift_')
          @key_bindings << KeyBinding.new(key:, semantic:, display_key:, description:)
        end

        def key_bindings = @key_bindings.freeze
      end
    end
  end
end
