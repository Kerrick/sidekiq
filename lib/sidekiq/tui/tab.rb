# frozen_string_literal: true

module Sidekiq
  module TUI
    # App-level mixin for tab fragments. Provides the Router DSL,
    # default empty key bindings, and class macros for common tab patterns.
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

        def map(envelope, key, description, help)
          display_key = key.to_s.delete_prefix('shift_')
          @key_bindings << KeyBinding.new(key: key.to_sym, envelope:, display_key:, description:, help:)
        end

        def key_bindings = @key_bindings.freeze

        private

        def register_table_bindings
          map :prev_page,         :h,       'Prev/Next Page', 'Use vim keys to move to prev/next page'
          map :next_page,         :l,       'Prev/Next Page', 'Use vim keys to move to prev/next page'
          map :row_up,            :k,       'Prev/Next Row',  'Use vim keys to move to prev/next row'
          map :row_down,          :j,       'Prev/Next Row',  'Use vim keys to move to prev/next row'
          map :toggle_select,     :x,       'Select',         'Select/deselect current row'
          map :toggle_select_all, :shift_A, 'Select All',     'Select/deselect All visible rows'
        end
      end
    end
  end
end

