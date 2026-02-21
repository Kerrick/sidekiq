# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared view helpers — styles, formatters, and reusable rendering lambdas.
    module Views
      HOTKEY_STYLE    = RatatuiRuby::Style::Style.new(modifiers: %i[bold underlined])
      TITLE_STYLE     = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:bold])
      HIGHLIGHT_STYLE = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:underlined])
      ALT_ROW_STYLE   = RatatuiRuby::Style::Style.new(bg: :dark_gray)
      ROW_HL_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :blue)
      FILTER_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray)
      BLINK_STYLE     = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray, modifiers: [:slow_blink])
      ERR_BORDER      = RatatuiRuby::Style::Style.new(fg: :red)

      FormatMemory = lambda { |rss_kb|
        return '0' if rss_kb.nil? || rss_kb.zero?

        if rss_kb < 100_000
          "#{rss_kb} KB"
        elsif rss_kb < 10_000_000
          "#{(rss_kb / 1024.0).to_i} MB"
        else
          "#{(rss_kb / (1024.0 * 1024.0)).round(1)} GB"
        end
      }

      RenderStats = lambda { |stats, tui|
        keys = %w[Processed Failed Busy Enqueued Retries Scheduled Dead]
        vals = [stats.processed, stats.failed, stats.busy, stats.enqueued,
                stats.retries, stats.scheduled, stats.dead]
        tui.paragraph(
          text: [keys.map { |k| k.ljust(12) }.join('  '), vals.map { |v| v.to_s.ljust(12) }.join('  ')],
          block: tui.block(title: 'Statistics', borders: [:all])
        )
      }

      RenderError = lambda { |error, tui|
        message = error.respond_to?(:error_message) ? error.error_message : error.to_s
        backtrace = error.respond_to?(:backtrace) ? Array(error.backtrace) : []
        header = [tui.text_line(
          spans: [tui.text_span(content: message, style: RatatuiRuby::Style::Style.new(modifiers: [:bold]))],
          alignment: :center
        )]
        lines = backtrace.map { |line| tui.text_line(spans: [tui.text_span(content: line)]) }
        tui.paragraph(text: header + lines, alignment: :left,
                      block: tui.block(title: 'Error', borders: [:all], border_style: ERR_BORDER))
      }
    end
  end
end
