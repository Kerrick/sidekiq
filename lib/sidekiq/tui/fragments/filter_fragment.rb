# frozen_string_literal: true

module Sidekiq
  module TUI
    # Pure state machine for filtering in set tabs.
    # No View — filter display is part of TableFragment's footer.
    # Bubbles FilterChanged on submit (enter) or cancel (esc).
    module FilterFragment
      include Rooibos::Router

      # Bubbled when the filter changes — SetFragment intercepts to trigger a re-fetch.
      class FilterChanged < Data.define(:envelope, :text)
        include Rooibos::Message::Predicates
      end

      Model = Data.define(:active, :text)
      Init = -> { Ractor.make_shareable Model.new(active: false, text: nil) }

      receive_routed :start_filter, lambda { |_, model|
        DebugLogger.info('FilterFragment StartFilter')
        model.with(active: true, text: '')
      }

      only when: ->(_, model) { model.active } do
        receive ->(message, _) { message.respond_to?(:text?) && message.text? && message.code.length == 1 },
                lambda { |message, model|
                  DebugLogger.info("FilterFragment AppendChar: #{message.code}")
                  model.with(text: "#{model.text}#{message.code}")
                }
        receive_events :backspace, ->(_, model) { model.with(text: (model.text || '').chop) }
        receive_events :enter, lambda { |_, model|
          DebugLogger.info("FilterFragment SubmitFilter: text=#{model.text}")
          [model.with(active: false),
           Rooibos::Command.bubble(FilterChanged.new(envelope: :filter, text: model.text))]
        }
        receive_events :esc, lambda { |_, model|
          DebugLogger.info('FilterFragment CancelFilter')
          [model.with(active: false, text: nil),
           Rooibos::Command.bubble(FilterChanged.new(envelope: :filter, text: nil))]
        }
      end

      Update = from_router
    end
  end
end
