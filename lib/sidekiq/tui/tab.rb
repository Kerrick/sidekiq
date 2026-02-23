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
          route :table, to: Table
          otherwise route_to: :table
          register_table_bindings
        end

        def has_set
          route :set, to: Set
          otherwise route_to: :set
          register_table_bindings
        end

        def fetch_command(fetch_class)
          const_set(:FetchCommand, ->(_model) { [fetch_class.new] })
        end

        def map(semantic, key, description)
          display_key = key.to_s.delete_prefix('shift_')
          @key_bindings << KeyBinding.new(key:, semantic:, display_key:, description:)
        end

        def key_bindings = @key_bindings.freeze

        private

        def register_table_bindings
          map :prev_page,         :h,       'Prev/Next Page'
          map :next_page,         :l,       'Prev/Next Page'
          map :row_up,            :k,       'Prev/Next Row'
          map :row_down,          :j,       'Prev/Next Row'
          map :toggle_select,     :x,       'Select'
          map :toggle_select_all, :shift_A, 'Select All'
        end
      end
    end
  end
end
