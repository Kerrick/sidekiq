# frozen_string_literal: true

module Sidekiq
  module TUI
    # Pure state machine for filtering.
    # No View — filter display is in the controls bar (Help::ControlsView).
    # Bubbles FilterChanged on submit (enter) or cancel (esc).
    module Filter
      include Rooibos::Router

      # Bubbled when the filter changes — Set intercepts to trigger a re-fetch.
      class FilterChanged < Data.define(:envelope, :text)
        include Rooibos::Message::Predicates
      end

      Model = Data.define(:focused?, :text)
      Init = -> { Ractor.make_shareable Model.new(:focused? => false, text: nil) }

      receive_routed :start_filter, lambda { |_, model|
        model.with(:focused? => true, text: "")
      }

      only when: ->(_, model) { model.focused? } do
        receive ->(message, _) { message.respond_to?(:text?) && message.text? && message.code.length == 1 },
          lambda { |message, model|
            model.with(text: "#{model.text}#{message.code}")
          }
        receive_events :backspace, ->(_, model) { model.with(text: (model.text || "").chop) }
        receive_events :enter, lambda { |_, model|
          [model.with(:focused? => false),
            Rooibos::Command.bubble(FilterChanged.new(envelope: :filter, text: model.text))]
        }
        receive_events :esc, lambda { |_, model|
          [model.with(:focused? => false, text: nil),
            Rooibos::Command.bubble(FilterChanged.new(envelope: :filter, text: nil))]
        }
      end

      Update = from_router
    end
  end
end
