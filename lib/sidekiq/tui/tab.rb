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

        def has_set(**actions)
          tab_name = name.split('::').last.downcase.to_sym
          set_class_name = "Sidekiq::#{name.split('::').last}Set"
          fetch_class = const_get(:Fetch)
          fetched_class = const_get(:Fetched)

          route :set, to: Set
          otherwise route_to: :set
          register_table_bindings

          # Inward: forward fetched data to Set
          forward_instances_of fetched_class, to: :set, as: :data_received

          # Outward: intercept action bubbles from Table → dispatch to AlterSetRows
          intercept_instances_of Table::ActionRequested, lambda { |message, model|
            action_name = actions[message.action] || message.action
            [model, AlterSetRows.new(set_class_name:, ids: message.ids, action_name:, tab: tab_name)]
          }

          # Outward: intercept fetch bubbles from Set → issue tab-specific fetch
          intercept_instances_of Set::FetchRequested, lambda { |message, model|
            [model, fetch_class.new(filter: message.filter, pager_page: message.pager_page,
                                    pager_size: message.pager_size)]
          }
        end

        def from_set = Data.define(:set)

        def set_init
          tab_name = name.split('::').last.downcase.to_sym
          fetch_class = const_get(:Fetch)
          model_class = const_get(:Model)
          lambda {
            model = Ractor.make_shareable(model_class.new(set: Set::Init[tab_name:]))
            [model, fetch_class.new(filter: '', pager_page: 1, pager_size: 25)]
          }
        end

        def set_view = ->(model, tui) { Set::View[model.set, tui] }

        def map(semantic, key, description, help)
          display_key = key.to_s.delete_prefix('shift_')
          @key_bindings << KeyBinding.new(key: key.to_sym, semantic:, display_key:, description:, help:)
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
