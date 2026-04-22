# frozen_string_literal: true

module Sidekiq
  module TUI
    module Tab
      # Mixin for sorted-set tabs (Scheduled, Retry, Dead). Including this
      # includes Tab, then `acts_as_sorted_set` wires routing/forwarding/intercepts
      # by convention.
      module SortedSet
        def self.included(base)
          base.include Tab
          base.extend SortedSetClassMethods
        end

        module SortedSetClassMethods
          def acts_as_sorted_set
            fetch_class = const_get(:Fetch)
            fetched_class = const_get(:Fetched)
            tab_name = name.split("::").last.downcase.to_sym
            set_class_name = "Sidekiq::#{name.split("::").last}Set"

            route :set, to: ::Sidekiq::TUI::SetContent
            otherwise route_to: :set

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

          def from_sorted_set
            Data.define(:set) do
              def filtering? = set.filter_model.focused?
            end
          end

          def sorted_set_init
            tab_name = name.split("::").last.downcase.to_sym
            fetch_class = const_get(:Fetch)
            model_class = const_get(:Model)
            lambda {
              model = Ractor.make_shareable(model_class.new(set: ::Sidekiq::TUI::SetContent::Init[tab_name:]))
              [model, fetch_class.new(filter: "", pager_page: 1, pager_size: 25)]
            }
          end

          def sorted_set_view = ->(model, tui) { ::Sidekiq::TUI::SetContent::View[model.set, tui] }
        end
      end
    end
  end
end
