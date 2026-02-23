# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default)

require "minitest/autorun"
require "minitest/pride"

require "rooibos/test_helper"

require "sidekiq/tui"

class TestMetricsTabView < Minitest::Test
  include Rooibos::TestHelper

  private

  def render_metrics(model)
    tui = RatatuiRuby::TUI.new
    widget = Sidekiq::TUI::MetricsTab::View.call(model, tui)
    RatatuiRuby.draw { |frame| frame.render_widget(widget, frame.area) }
    buffer_content
  end

  def loaded_model
    # MetricsFetched datasets are plain hashes with :name and :data keys
    datasets = [
      { name: "HardWorker", data: Array.new(60) { |i| [i, 10] } }
    ]
    init = Sidekiq::TUI::MetricsTab::Init[]
    init.with(loading: false, datasets: datasets, starts_at: "16:00", ends_at: "17:00")
  end

  public

  def test_skeleton_state_snapshot
    with_test_terminal(120, 20) do
      render_metrics(Sidekiq::TUI::MetricsTab::Init[])
      assert_snapshots("metrics_tab_skeleton")
    end
  end

  def test_loaded_state_snapshot
    with_test_terminal(120, 20) do
      render_metrics(loaded_model)
      assert_snapshots("metrics_tab_loaded")
    end
  end
end
