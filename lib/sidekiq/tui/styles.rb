# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared visual design tokens — the TUI's stylesheet.
    module Styles
      style = RatatuiRuby::TUI.new.method(:style)

      HOTKEY     = style[modifiers: %i[bold underlined]]
      TITLE      = style[fg: :red, modifiers: [:bold]]
      HIGHLIGHT  = style[fg: :red, modifiers: [:underlined]]
      ALT_ROW    = style[bg: :dark_gray]
      ROW_HL     = style[fg: :white, bg: :blue]
      FILTER     = style[fg: :white, bg: :dark_gray]
      BLINK      = style[fg: :white, bg: :dark_gray, modifiers: [:slow_blink]]
      ERR_BORDER = style[fg: :red]
    end
  end
end
