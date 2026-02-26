# frozen_string_literal: true

module Sidekiq
  module TUI
    module Tab
      # Mixin for sorted-set tabs (Scheduled, Retry, Dead). Including this
      # includes Tab, then wires routing/forwarding/intercepts by convention.
      module Set
        def self.included(base)
          base.include Tab
          base.extend SetClassMethods

          fetch_class = base.const_get(:Fetch)
          fetched_class = base.const_get(:Fetched)
          tab_name = base.name.split("::").last.downcase.to_sym
          set_class_name = "Sidekiq::#{base.name.split("::").last}Set"

          base.class_eval do
            route :set, to: ::Sidekiq::TUI::SetContent
            otherwise route_to: :set
            register_table_bindings

            forward_instances_of fetched_class, to: :set, as: :data_received

            intercept_instances_of ::Sidekiq::TUI::SetContent::FetchRequested, lambda { |message, model|
              [model, fetch_class.new(filter: message.filter, pager_page: message.pager_page,
                pager_size: message.pager_size)]
            }

            observe_instances_of SetRows::Altered, lambda { |_, model|
              fetch_class.new(filter: model.set.filter_model.text,
                pager_page: model.set.pager.page,
                pager_size: model.set.pager.size)
            }
            forward_instances_of SetRows::Altered, to: :set, as: :rows_altered

            intercept_instances_of Table::Request, lambda { |message, model|
              [model, SetRows::Alter.new(set_class_name:, ids: message.ids, method_name: message.envelope, tab: tab_name)]
            }
          end
        end

        module SetClassMethods
          def from_set = Data.define(:set)

          def set_init
            tab_name = name.split("::").last.downcase.to_sym
            fetch_class = const_get(:Fetch)
            model_class = const_get(:Model)
            lambda {
              model = Ractor.make_shareable(model_class.new(set: ::Sidekiq::TUI::SetContent::Init[tab_name:]))
              [model, fetch_class.new(filter: "", pager_page: 1, pager_size: 25)]
            }
          end

          def set_view = ->(model, tui) { ::Sidekiq::TUI::SetContent::View[model.set, tui] }
        end
      end
    end
  end
end
