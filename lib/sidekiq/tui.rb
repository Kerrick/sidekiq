# frozen_string_literal: true

# https://www.rooibos.run
gem "rooibos", ">= 0.7.0"
require "rooibos"

RatatuiRuby.debug_mode!

require "sidekiq/api"
require "sidekiq/paginator"

require "logger"
Sidekiq.default_configuration.logger = Logger.new(IO::NULL)

module Sidekiq
  module TUI
    class KeyBinding < Data.define(:key, :envelope, :display_key, :description, :help); end
  end
end

require_relative "tui/styles"
require_relative "tui/tab"
require_relative "tui/tab/set"
require_relative "tui/repos"
require_relative "tui/fragments/table"
require_relative "tui/fragments/home"
require_relative "tui/fragments/busy"
require_relative "tui/fragments/queues"
require_relative "tui/fragments/filter"
require_relative "tui/pager_state"
require_relative "tui/fragments/set_content"
require_relative "tui/fragments/scheduled"
require_relative "tui/fragments/retry"
require_relative "tui/fragments/dead"
require_relative "tui/fragments/metrics"
require_relative "tui/fragments/stats"
require_relative "tui/fragments/help"
require_relative "tui/fragments/tabs"
require_relative "tui/root"

module Sidekiq
  module TUI
    module Help
      ALL_BINDINGS = [
        ESC_BINDING,
        *Tabs::TAB_MODULES.values.flat_map(&:key_bindings).uniq(&:display_key),
        *COMMON_BINDINGS.reject { |b| b.display_key == "?" }
      ].uniq(&:display_key).freeze
    end
  end
end
