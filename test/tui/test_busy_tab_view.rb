# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default)

require "minitest/autorun"
require "minitest/pride"

require "rooibos/test_helper"

require "sidekiq/tui"

class TestBusyTabView < Minitest::Test
  include Rooibos::TestHelper

  private

  def render_busy(model)
    tui = RatatuiRuby::TUI.new
    widget = Sidekiq::TUI::BusyTab::View.call(model, tui)
    RatatuiRuby.draw { |frame| frame.render_widget(widget, frame.area) }
    buffer_content
  end

  def loaded_model
    processes = [
      Sidekiq::TUI::Processes::Record.new(
        identity: "worker1:1234:abc", hostname: "worker1", pid: "1234",
        started_at: Time.utc(2026, 2, 22, 16, 0, 0), rss_kb: 102_400,
        concurrency: 10, busy: 3, leader: true, stopping: false
      ),
      Sidekiq::TUI::Processes::Record.new(
        identity: "worker2:5678:def", hostname: "worker2", pid: "5678",
        started_at: Time.utc(2026, 2, 22, 17, 0, 0), rss_kb: 51_200,
        concurrency: 5, busy: 2, leader: false, stopping: false
      )
    ]
    init = Sidekiq::TUI::BusyTab::Init[]
    init.with(
      loading: false,
      table: init.table.with(row_ids: processes.map(&:identity)),
      processes: processes, work_set_size: 5
    )
  end

  public

  def test_skeleton_state_snapshot
    with_test_terminal(120, 20) do
      render_busy(Sidekiq::TUI::BusyTab::Init[])
      assert_snapshots("busy_tab_skeleton")
    end
  end

  def test_loaded_state_snapshot
    with_test_terminal(120, 20) do
      render_busy(loaded_model)
      assert_snapshots("busy_tab_loaded")
    end
  end
end
