# frozen_string_literal: true

module Sidekiq
  module TUI
    module Help
      Model = Data.define(:expanded, :active_tab, :redis_url)

      Init = lambda {
        [Ractor.make_shareable(Model.new(expanded: false, active_tab: :home, redis_url: 'N/A')), nil]
      }

      ESC_BINDING = KeyBinding.new(
        key: nil, semantic: nil, display_key: 'Esc', description: 'Close', help: 'Close'
      )

      COMMON_BINDINGS = [
        KeyBinding.new(key: nil, semantic: nil, display_key: '?', description: 'Help', help: 'Help'),
        KeyBinding.new(key: nil, semantic: nil, display_key: '←/→', description: 'Select Tab', help: 'Move between tabs'),
        KeyBinding.new(key: nil, semantic: nil, display_key: 'q', description: 'Quit', help: 'Quit')
      ].freeze

      AllBindings = lambda {
        @all_bindings ||= [
          ESC_BINDING,
          *Sidekiq::TUI::TAB_MODULES.values.flat_map(&:key_bindings).uniq(&:display_key),
          *COMMON_BINDINGS.reject { |b| b.display_key == '?' }
        ].uniq(&:display_key).freeze
      }

      ControlsFor = lambda { |active_tab|
        tab_module = TAB_MODULES[active_tab]
        return COMMON_BINDINGS if active_tab == :home

        COMMON_BINDINGS + tab_module.key_bindings
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
        spans = KeyBindingsView[ControlsFor[model.active_tab], tui]
        tui.paragraph(
          text: [tui.text_line(spans: spans),
                 tui.text_line(spans: [tui.text_span(content: "Redis: #{model.redis_url} "),
                                       tui.text_span(content: "Current Time: #{Time.now.utc}")])],
          block: tui.block(title: 'Controls', borders: [:all])
        )
      }

      # Full help overlay — hardcoded bindings matching upstream (not context-sensitive).
      ExpandedView = lambda { |_model, tui|
        text_lines = [tui.text_line(spans: ['Welcome to the Sidekiq Terminal UI'], alignment: :center)] +
                     AllBindings[].map do |binding|
                       tui.text_line(spans: [tui.text_span(content: binding.display_key, style: Styles::HOTKEY),
                                             tui.text_span(content: ": #{binding.help}")])
                     end
        content = tui.block(title: Sidekiq::NAME, borders: [:all], title_style: Styles::TITLE,
                            children: [tui.paragraph(text: text_lines)])
        ctrl = tui.paragraph(
          text: [tui.text_line(spans: [tui.text_span(content: 'Esc', style: Styles::HOTKEY),
                                       tui.text_span(content: ': Close  ')])],
          block: tui.block(title: 'Controls', borders: [:all])
        )
        tui.layout(direction: :vertical,
                   constraints: [tui.constraint_fill(1), tui.constraint_length(4)],
                   children: [content, ctrl])
      }

      Update = lambda { |message, model|
        case message
        in :toggle then model.with(expanded: !model.expanded)
        else model
        end
      }
    end
  end
end
