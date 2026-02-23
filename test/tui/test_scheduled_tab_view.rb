# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default)

require "minitest/autorun"
require "minitest/pride"

require "rooibos/test_helper"

# Require the TUI (loads Rooibos, RatatuiRuby, and all tab modules)
require "sidekiq/tui"

class TestScheduledView < Minitest::Test
  include Rooibos::TestHelper

  private

  # Renders the Scheduled::View into the test terminal buffer and returns buffer_content.
  def render_scheduled(model)
    tui = RatatuiRuby::TUI.new
    widget = Sidekiq::TUI::Scheduled::View.call(model, tui)
    RatatuiRuby.draw { |frame| frame.render_widget(widget, frame.area) }
    buffer_content
  end

  # Returns [row, col] of the first occurrence of text in the buffer lines.
  def position_of(lines, text)
    lines.each_with_index do |line, row|
      col = line.index(text)
      return [row, col] if col
    end
    nil
  end

  def loaded_model
    set_model = Sidekiq::TUI::SetFragment::Init[tab_name: :scheduled]
    loaded_set = set_model.with(
      loading: false,
      pager: set_model.pager.with(current_page: 12, total: 345, next_page: 13, page: 12, size: 25),
      rows: Array.new(25) { |i|
        { id: "#{1000 + i}.0|job#{i}", at: "2026-02-22 16:#{format("%02d", i)}:00 UTC", queue: "default",
          display_class: "HardWorker", display_args: "[#{i}]" }
      },
      table: set_model.table.with(row_ids: Array.new(25) { |i| "#{1000 + i}.0|job#{i}" })
    )
    Sidekiq::TUI::Scheduled::Model.new(set: loaded_set)
  end

  def normalize_timestamp(lines)
    lines.map { |l| l.gsub(/Current Time: [^\s]+/, "Current Time: TIMESTAMP") }
  end

  public

  def test_init_state_snapshot
    with_test_terminal(120, 30) do
      render_scheduled(Sidekiq::TUI::Scheduled::Init[])
      assert_snapshots("scheduled_tab_init", &method(:normalize_timestamp))
    end
  end

  def test_loaded_state_snapshot
    with_test_terminal(120, 30) do
      render_scheduled(loaded_model)
      assert_snapshots("scheduled_tab_loaded", &method(:normalize_timestamp))
    end
  end

  # The layout must not shift when data loads after a tab switch.
  # After switching tabs, Init[] renders an empty table. A few frames later,
  # the fetched data arrives. Every label — table header, footer —
  # must be at the same (row, column) in both frames, or the user sees a jarring jump.
  def test_layout_does_not_shift_between_init_and_loaded_states
    init_lines = nil
    loaded_lines = nil

    with_test_terminal(120, 30) do
      init_lines = render_scheduled(Sidekiq::TUI::Scheduled::Init[])
    end

    with_test_terminal(120, 30) do
      loaded_lines = render_scheduled(loaded_model)
    end

    # Every label that appears in both states must be at the exact same (row, col).
    labels = [
      # Block title
      "Scheduled",
      # Table headers
      "When", "Queue", "Job", "Arguments",
      # Footer
      "Page:", "Count:", "Total:"
    ]

    labels.each do |label|
      init_pos = position_of(init_lines, label)
      loaded_pos = position_of(loaded_lines, label)

      refute_nil init_pos, "Init state must contain #{label.inspect}"
      refute_nil loaded_pos, "Loaded state must contain #{label.inspect}"

      assert_equal init_pos, loaded_pos,
        "#{label.inspect} shifted from (row=#{init_pos[0]}, col=#{init_pos[1]}) " \
        "to (row=#{loaded_pos[0]}, col=#{loaded_pos[1]})"
    end
  end
end
