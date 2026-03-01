# frozen_string_literal: true

module Sidekiq
  module TUI
    include Rooibos::Router

    Model = Data.define(:tabs, :stats, :help, :error)

    Init = lambda {
      tick = Rooibos::Command.tick(1, :clock)
      tabs_model, tabs_cmd = Tabs::Init[]
      stats_model, stats_cmd = Stats::Init[]
      help_model, _help_cmd = Help::Init[]
      model = Ractor.make_shareable Model.new(
        tabs: tabs_model, stats: stats_model, help: help_model, error: nil
      )
      [model, Rooibos::Command.batch(stats_cmd, tabs_cmd, tick)]
    }

    View = lambda { |model, tui|
      stats_view = Stats::View[model.stats, tui]
      content = if model.error
        ErrorView[model.error, tui]
      else
        Tabs::View[model.tabs, tui, stats_view]
      end
      controls = Help::ControlsView[model.help, tui]
      base = tui.layout(
        direction: :vertical,
        constraints: [tui.constraint_fill(1), tui.constraint_length(4)],
        children: [content, controls]
      )
      Help::View[model.help, tui, base]
    }

    ErrorView = lambda { |error, tui|
      error_msg = error.respond_to?(:error_message) ? error.error_message : error.to_s
      error_bt = error.respond_to?(:backtrace) ? Array(error.backtrace) : []
      header = [tui.text_line(
        spans: [tui.text_span(content: error_msg, style: RatatuiRuby::Style::Style.new(modifiers: [:bold]))],
        alignment: :center
      )]
      lines = error_bt.map { |line| tui.text_line(spans: [tui.text_span(content: line)]) }
      tui.paragraph(text: header + lines, alignment: :left,
        block: tui.block(title: "Error", borders: [:all], border_style: Styles::ERR_BORDER))
    }

    # --- Fragment routes ---

    route :tabs, to: Tabs
    route :stats, to: Stats
    route :help, to: Help

    # --- Help overlay (modal — swallows all events) ---

    only when: ->(_, model) { model.help.expanded } do
      forward_events %i[esc ?], to: :help, as: :hide
      otherwise route_to: :help
    end

    # --- Global keys ---

    action :quit, -> { Rooibos::Command.exit }
    only when: ->(_, model) { !Tabs::IsSetFiltering[nil, model.tabs] } do
      receive_events %i[q ctrl_c], :quit
      forward_events :"?", to: :help, as: :show
    end

    route_to :tabs do
      forward_events :left, as: :prev_tab
      forward_events :right, as: :next_tab
    end

    observe_instances_of Tabs::ActiveTabChanged, lambda { |message, model|
      [model.with(error: nil), Stats::Fetch.new]
    }

    forward_instances_of Tabs::ActiveTabChanged, to: :help

    # --- Timer ---

    observe_instances_of Rooibos::Message::Timer, lambda { |_, model|
      [model, Rooibos::Command.tick(1, :clock)]
    }

    forward_instances_of Rooibos::Message::Timer, broadcast: true, as: :clock

    # --- Data fetch results ---

    forward_instances_of Stats::Fetched, broadcast_to: [:stats, :tabs, :help]

    receive_instances_of DataFetchError, lambda { |message, model|
      model.with(error: message)
    }

    # --- Forward unhandled messages to Tabs ---

    otherwise route_to: :tabs

    Update = from_router
  end
end
