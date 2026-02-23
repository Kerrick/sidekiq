# frozen_string_literal: true

# https://www.rooibos.run
gem 'rooibos', '>= 0.7.0'
require 'rooibos'

RatatuiRuby.debug_mode!

require 'sidekiq/api'
require 'sidekiq/paginator'

require 'logger'
Sidekiq.default_configuration.logger = Logger.new(IO::NULL)

require_relative 'tui/tabs'
require_relative 'tui/data'
require_relative 'tui/views'
require_relative 'tui/messages'
require_relative 'tui/commands'
require_relative 'tui/fragments/table_fragment'
require_relative 'tui/tabs/home_tab'
require_relative 'tui/tabs/busy_tab'
require_relative 'tui/tabs/queues_tab'
require_relative 'tui/fragments/filter_fragment'
require_relative 'tui/fragments/set_fragment'
require_relative 'tui/tabs/scheduled_tab'
require_relative 'tui/tabs/retries_tab'
require_relative 'tui/tabs/dead_tab'
require_relative 'tui/tabs/metrics_tab'
require_relative 'tui/root'

DebugLogger = Logger.new('tui.log')
def log(*x)
  x.each { |item| DebugLogger.info { item } }
end
