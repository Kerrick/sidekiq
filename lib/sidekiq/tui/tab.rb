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

        def has_filter(on_changed: nil)
          route :filter_model, to: Filter

          forward_routed :start_filter, to: :filter_model, as: :start_filter

          receive_routed :start_filter, lambda { |_, model|
            [model, Rooibos::Command.bubble(
              Tabs::FilterChanged.new(text: "", :focused? => true)
            )]
          }

          only when: ->(_, model) { model.filter_model.focused? } do
            otherwise route_to: :filter_model
          end

          return unless on_changed

          intercept_instances_of Filter::FilterChanged, lambda { |message, model|
            new_model, tab_specific_command = on_changed.call(message, model)
            [new_model, Rooibos::Command.batch(
              *[tab_specific_command, Rooibos::Command.bubble(
                Tabs::FilterChanged.new(text: message.text, :focused? => false)
              )].compact
            )]
          }
        end
      end
    end
  end
end
