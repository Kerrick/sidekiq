# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared value objects and action lambdas used across fragments.

    TableState = Data.define(:rows, :row_ids, :selected, :selected_row_index) do
      def selected?(id) = selected.include?(id)
      def action_ids = selected.empty? ? (row_ids.empty? ? [] : [row_ids[selected_row_index]]) : selected
    end

    PagerState = Data.define(:page, :size, :current_page, :total, :next_page)

    EMPTY_TABLE = Ractor.make_shareable(
      TableState.new(rows: [].freeze, row_ids: [].freeze, selected: [].freeze, selected_row_index: 0)
    )
    EMPTY_PAGER = Ractor.make_shareable(
      PagerState.new(page: 1, size: 25, current_page: 1, total: 0, next_page: nil)
    )
    EMPTY_STATS = Ractor.make_shareable(
      { processed: 0, failed: 0, busy: 0, enqueued: 0, retries: 0, scheduled: 0, dead: 0 }.freeze
    )

    # --- Shared action lambdas (semantic message handlers) ---

    RowDown          = ->(_, model) { model.with(table: model.table.with(selected_row_index: model.table.row_ids.empty? ? 0 : (model.table.selected_row_index + 1) % model.table.row_ids.size)) }
    RowUp            = ->(_, model) { model.with(table: model.table.with(selected_row_index: model.table.row_ids.empty? ? 0 : (model.table.selected_row_index - 1) % model.table.row_ids.size)) }
    ToggleSelect     = ->(_, model) {
      t = model.table
      return model if t.row_ids.empty?
      id = t.row_ids[t.selected_row_index]
      new_sel = t.selected.include?(id) ? (t.selected - [id]).freeze : (t.selected + [id]).freeze
      model.with(table: t.with(selected: new_sel))
    }
    ToggleSelectAll  = ->(_, model) {
      t = model.table
      model.with(table: t.with(selected: t.selected.empty? ? t.row_ids.dup.freeze : [].freeze))
    }
    ClearSelection   = ->(table) { table.with(selected: [].freeze) }

    # --- Shared view helpers ---

    HOTKEY_STYLE = RatatuiRuby::Style::Style.new(modifiers: [:bold, :underlined])
    TITLE_STYLE  = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:bold])
    HIGHLIGHT_STYLE = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:underlined])
    ALT_ROW_STYLE   = RatatuiRuby::Style::Style.new(bg: :dark_gray)
    ROW_HL_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :blue)
    FILTER_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray)
    BLINK_STYLE     = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray, modifiers: [:slow_blink])
    BOLD_STYLE      = RatatuiRuby::Style::Style.new(modifiers: [:bold])
    ERR_BORDER      = RatatuiRuby::Style::Style.new(fg: :red)

    RenderStats = ->(stats, tui) {
      keys = %w[Processed Failed Busy Enqueued Retries Scheduled Dead]
      vals = [stats[:processed], stats[:failed], stats[:busy], stats[:enqueued],
              stats[:retries], stats[:scheduled], stats[:dead]]
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
      msg = error.is_a?(Exception) ? error.message : error.to_s
      tui.paragraph(text: msg, alignment: :center,
                    block: tui.block(title: "Error", borders: [:all], border_style: ERR_BORDER))
    }
  end
end
