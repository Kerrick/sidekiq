# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default)

require "minitest/autorun"
require "minitest/pride"

require "rooibos/test_helper"

require "sidekiq/tui"

class TestHomeTabView < Minitest::Test
  include Rooibos::TestHelper

  private

  def render_home(model)
    tui = RatatuiRuby::TUI.new
    widget = Sidekiq::TUI::HomeTab::View.call(model, tui)
    RatatuiRuby.draw { |frame| frame.render_widget(widget, frame.area) }
    buffer_content
  end

  def loaded_model
    redis_info = Sidekiq::TUI::RedisInfo::Record.new(
      version: "7.2.4", uptime_days: "42",
      connected_clients: "12", used_memory: "4.2MB", peak_memory: "8.1MB"
    )
    init = Sidekiq::TUI::HomeTab::Init[]
    init.with(loading: false, redis_info: redis_info)
  end

  public

  def test_skeleton_state_snapshot
    Time.stub(:now, Time.at(100)) do
      with_test_terminal(120, 20) do
        render_home(Sidekiq::TUI::HomeTab::Init[])
        assert_snapshots("home_tab_skeleton")
      end
    end
  end

  def test_loaded_state_snapshot
    Time.stub(:now, Time.at(101)) do
      with_test_terminal(120, 20) do
        render_home(loaded_model)
        assert_snapshots("home_tab_loaded")
      end
    end
  end
end
