# frozen_string_literal: true

module Sidekiq
  module TUI
    module Tab
      # Mixin for sorted-set tabs (Scheduled, Retry, Dead). Including this
      # includes Tab, then wires routing/forwarding/intercepts by convention.
      # Only the action mapping (has_set) is tab-specific.
      module Set
        def self.included(base)
          base.include Tab
          base.extend SetClassMethods

          fetch_class = base.const_get(:Fetch)
          fetched_class = base.const_get(:Fetched)

          base.class_eval do
            route :set, to: ::Sidekiq::TUI::Set
            otherwise route_to: :set
            register_table_bindings

            forward_instances_of fetched_class, to: :set, as: :data_received

            intercept_instances_of ::Sidekiq::TUI::Set::FetchRequested, lambda { |message, model|
              [model, fetch_class.new(filter: message.filter, pager_page: message.pager_page,
                                      pager_size: message.pager_size)]
            }
          end
        end

        module SetClassMethods
          def envelopes(**action_map)
            tab_name = name.split('::').last.downcase.to_sym
            set_class_name = "Sidekiq::#{name.split('::').last}Set"

            intercept_instances_of Table::ActionRequested, lambda { |message, model|
              method_name = action_map[message.action] || message.action
              [model, AlterSetRows.new(set_class_name:, ids: message.ids, method_name:,
                                       envelope: message.action, tab: tab_name)]
            }
          end

          def from_set = Data.define(:set)

          def set_init
            tab_name = name.split('::').last.downcase.to_sym
            fetch_class = const_get(:Fetch)
            model_class = const_get(:Model)
            lambda {
              model = Ractor.make_shareable(model_class.new(set: ::Sidekiq::TUI::Set::Init[tab_name:]))
              [model, fetch_class.new(filter: '', pager_page: 1, pager_size: 25)]
            }
          end

          def set_view = ->(model, tui) { ::Sidekiq::TUI::Set::View[model.set, tui] }
        end
      end
    end
  end
end
