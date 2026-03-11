# frozen_string_literal: true

module Sidekiq
  module TUI
    module Help
      include Rooibos::Router

      Model = Data.define(:expanded, :controls, :redis_url, :current_time)

      Init = lambda {
        [Ractor.make_shareable(Model.new(expanded: false, controls: KeyMap.controls_for(:home), redis_url: "N/A", current_time: "…")), nil]
      }


      KeyBindingsView = lambda { |bindings, tui|
        bindings.flat_map do |binding|
          [tui.text_span(content: binding.display_key, style: Styles::HOTKEY),
            tui.text_span(content: ": #{binding.description}  ")]
        end
      }

      # Primary entry point — wraps base widget with help overlay when expanded.
      View = lambda { |model, tui, base|
        if model.expanded
          tui.overlay(layers: [base, tui.clear, ExpandedView[model, tui]])
        else
          base
        end
      }

      # Controls bar — rendered by root as the bottom child of its layout.
      ControlsView = lambda { |model, tui|
        spans = KeyBindingsView[model.controls, tui]
        tui.paragraph(
          text: [tui.text_line(spans: spans),
            tui.text_line(spans: [tui.text_span(content: "Redis: #{model.redis_url} "),
              tui.text_span(content: "Current Time: #{model.current_time}")])],
          block: tui.block(title: "Controls", borders: [:all])
        )
      }

      # Full help overlay — hardcoded bindings matching upstream (not context-sensitive).
      ExpandedView = lambda { |_model, tui|
        text_lines = [tui.text_line(spans: ["Welcome to the Sidekiq Terminal UI"], alignment: :center)] +
          KeyMap::ALL.map do |binding|
            tui.text_line(spans: [tui.text_span(content: binding.display_key, style: Styles::HOTKEY),
              tui.text_span(content: ": #{binding.help}")])
          end
        content = tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Styles::TITLE,
          children: [tui.paragraph(text: text_lines)])
        ctrl = tui.paragraph(
          text: [tui.text_line(spans: [tui.text_span(content: "Esc", style: Styles::HOTKEY),
            tui.text_span(content: ": Close  ")])],
          block: tui.block(title: "Controls", borders: [:all])
        )
        tui.layout(direction: :vertical,
          constraints: [tui.constraint_fill(1), tui.constraint_length(4)],
          children: [content, ctrl])
      }

      receive_routed :show, ->(_, model) { model.with(expanded: true) }
      receive_routed :hide, ->(_, model) { model.with(expanded: false) }
      receive_routed :clock, ->(message, model) { model.with(current_time: message.event.time.getutc.to_s) }
      receive_instances_of Stats::Fetched, ->(message, model) { model.with(redis_url: message.redis_url) }
      receive_instances_of Tabs::ActiveTabChanged, ->(message, model) { model.with(controls: KeyMap.controls_for(message.tab)) }

      Update = from_router
    end
  end
end

