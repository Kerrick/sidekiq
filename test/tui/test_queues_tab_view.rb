# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default)

require "minitest/autorun"
require "minitest/pride"

require "rooibos/test_helper"

require "sidekiq/tui"

class TestQueuesTabView < Minitest::Test
  include Rooibos::TestHelper

  private

  def render_queues(model)
    tui = RatatuiRuby::TUI.new
    widget = Sidekiq::TUI::QueuesTab::View.call(model, tui)
    RatatuiRuby.draw { |frame| frame.render_widget(widget, frame.area) }
    buffer_content
  end

  def loaded_model
    queues = [
      Sidekiq::TUI::QueueData.new(name: "default", size: 42, latency: 1.5, paused: false),
      Sidekiq::TUI::QueueData.new(name: "critical", size: 7, latency: 0.02, paused: false),
      Sidekiq::TUI::QueueData.new(name: "mailers", size: 0, latency: 0.0, paused: false)
    ]
    init = Sidekiq::TUI::QueuesTab::Init[]
    init.with(
      loading: false,
      table: init.table.with(row_ids: queues.map(&:name)),
      queues: queues, pro: false
    )
  end

  public

  def test_skeleton_state_snapshot
    with_test_terminal(120, 20) do
      render_queues(Sidekiq::TUI::QueuesTab::Init[])
      assert_snapshots("queues_tab_skeleton")
    end
  end

  def test_loaded_state_snapshot
    with_test_terminal(120, 20) do
      render_queues(loaded_model)
      assert_snapshots("queues_tab_loaded")
    end
  end
end
