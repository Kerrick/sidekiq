# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared view helpers — styles, formatters, and reusable rendering lambdas.
    module Views
      HOTKEY_STYLE    = RatatuiRuby::Style::Style.new(modifiers: [:bold, :underlined])
      TITLE_STYLE     = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:bold])
      HIGHLIGHT_STYLE = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:underlined])
      ALT_ROW_STYLE   = RatatuiRuby::Style::Style.new(bg: :dark_gray)
      ROW_HL_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :blue)
      FILTER_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray)
      BLINK_STYLE     = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray, modifiers: [:slow_blink])
      ERR_BORDER      = RatatuiRuby::Style::Style.new(fg: :red)

      FormatMemory = ->(rss_kb) {
        return "0" if rss_kb.nil? || rss_kb == 0
        if rss_kb < 100_000
          "#{rss_kb} KB"
        elsif rss_kb < 10_000_000
          "#{(rss_kb / 1024.0).to_i} MB"
        else
          "#{(rss_kb / (1024.0 * 1024.0)).round(1)} GB"
        end
      }

      RenderStats = ->(stats, tui) {
        keys = %w[Processed Failed Busy Enqueued Retries Scheduled Dead]
        vals = [stats.processed, stats.failed, stats.busy, stats.enqueued,
                stats.retries, stats.scheduled, stats.dead]
        tui.paragraph(
          text: [keys.map { |k| k.ljust(12) }.join("  "), vals.map { |v| v.to_s.ljust(12) }.join("  ")],
          block: tui.block(title: "Statistics", borders: [:all])
        )
      }

      RenderTableWidget = ->(tui, table, header:, widths:, title:, rows:, pager: nil, filter_state: nil) {
        page = pager&.current_page || 1
        total = pager&.total || table.rows.size
        footer = ["", "Page: #{page}", "Count: #{table.rows.size}", "Total: #{total}"]
        footer << "Selected: #{table.selected.size}" unless table.selected.empty?
        if filter_state
          spans = [tui.text_span(content: "Filter: ", style: FILTER_STYLE),
                   tui.text_span(content: filter_state[:filter] || "", style: FILTER_STYLE)]
          spans << tui.text_span(content: "_", style: BLINK_STYLE) if filter_state[:filtering]
          footer << tui.text_line(spans: spans)
        end
        tui.table(highlight_symbol: "➡️", selected_row: table.selected_row_index,
                  row_highlight_style: ROW_HL_STYLE, footer: footer,
                  header: header, widths: widths, rows: rows,
                  block: tui.block(title: title, borders: :all))
      }

      RenderError = ->(error, tui) {
        text = error.is_a?(Exception) ? error.message : error.to_s
        tui.paragraph(text: text, alignment: :center,
                      block: tui.block(title: "Error", borders: [:all], border_style: ERR_BORDER))
      }
    end
  end
end
