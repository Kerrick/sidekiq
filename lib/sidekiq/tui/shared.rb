# frozen_string_literal: true

module Sidekiq
  module TUI
    # Shared value objects and action lambdas used across fragments.

    Stats = Data.define(:processed, :failed, :busy, :enqueued, :retries, :scheduled, :dead)
    RedisInfo = Data.define(:version, :uptime_days, :connected_clients, :used_memory, :peak_memory)
    BusyStatus = Data.define(:processes, :threads, :busy, :utilization, :rss)

    TableState = Data.define(:rows, :row_ids, :selected, :selected_row_index) do
      def selected?(id) = selected.include?(id)
      def action_ids = selected.empty? ? (row_ids.empty? ? [] : [row_ids[selected_row_index]]) : selected
    end

    PagerState = Data.define(:page, :size, :current_page, :total, :next_page)

    EMPTY_TABLE = Ractor.make_shareable(
      TableState.new(rows: [], row_ids: [], selected: [], selected_row_index: 0)
    )
    EMPTY_PAGER = Ractor.make_shareable(
      PagerState.new(page: 1, size: 25, current_page: 1, total: 0, next_page: nil)
    )
    EMPTY_STATS = Ractor.make_shareable(
      Stats.new(processed: 0, failed: 0, busy: 0, enqueued: 0, retries: 0, scheduled: 0, dead: 0)
    )
    EMPTY_REDIS_INFO = Ractor.make_shareable(
      RedisInfo.new(version: "N/A", uptime_days: "N/A", connected_clients: "N/A",
                    used_memory: "N/A", peak_memory: "N/A")
    )
    EMPTY_BUSY_STATUS = Ractor.make_shareable(
      BusyStatus.new(processes: "0", threads: "0", busy: "0", utilization: "0%", rss: "0")
    )

    # --- Shared action lambdas (semantic message handlers) ---

    RowDown = ->(_, model) {
      return model if model.table.row_ids.empty?
      model.with(table: model.table.with(selected_row_index: (model.table.selected_row_index + 1) % model.table.row_ids.size))
    }
    RowUp = ->(_, model) {
      return model if model.table.row_ids.empty?
      model.with(table: model.table.with(selected_row_index: (model.table.selected_row_index - 1) % model.table.row_ids.size))
    }
    ToggleSelect = ->(_, model) {
      table = model.table
      return model if table.row_ids.empty?
      id = table.row_ids[table.selected_row_index]
      new_sel = table.selected.include?(id) ? table.selected - [id] : table.selected + [id]
      model.with(table: table.with(selected: new_sel))
    }
    ToggleSelectAll = ->(_, model) {
      table = model.table
      model.with(table: table.with(selected: table.selected.empty? ? table.row_ids.dup : []))
    }
    ClearSelection = ->(table) { table.with(selected: []) }

    # --- Shared view helpers ---

    HOTKEY_STYLE    = RatatuiRuby::Style::Style.new(modifiers: [:bold, :underlined])
    TITLE_STYLE     = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:bold])
    HIGHLIGHT_STYLE = RatatuiRuby::Style::Style.new(fg: :red, modifiers: [:underlined])
    ALT_ROW_STYLE   = RatatuiRuby::Style::Style.new(bg: :dark_gray)
    ROW_HL_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :blue)
    FILTER_STYLE    = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray)
    BLINK_STYLE     = RatatuiRuby::Style::Style.new(fg: :white, bg: :dark_gray, modifiers: [:slow_blink])
    BOLD_STYLE      = RatatuiRuby::Style::Style.new(modifiers: [:bold])
    ERR_BORDER      = RatatuiRuby::Style::Style.new(fg: :red)

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
      message = error.is_a?(Exception) ? error.message : error.to_s
      tui.paragraph(text: message, alignment: :center,
                    block: tui.block(title: "Error", borders: [:all], border_style: ERR_BORDER))
    }
  end
end
