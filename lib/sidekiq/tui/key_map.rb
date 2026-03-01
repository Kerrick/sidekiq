# frozen_string_literal: true

module Sidekiq
  module TUI
    module KeyMap
      # Global
      QUIT     = KeyBinding.new(key: :q,      envelope: :quit,     display_key: "q",   description: "Quit",       help: "Quit")
      QUIT_ALT = KeyBinding.new(key: :ctrl_c, envelope: :quit,     display_key: "^C",  description: "Quit",       help: "Quit")
      HELP     = KeyBinding.new(key: :"?",    envelope: :show,     display_key: "?",   description: "Help",       help: "Help")
      ESC      = KeyBinding.new(key: :esc,    envelope: :hide,     display_key: "Esc", description: "Close",      help: "Close")
      PREV_TAB = KeyBinding.new(key: :left,   envelope: :prev_tab, display_key: "←/→", description: "Select Tab", help: "Move between tabs")
      NEXT_TAB = KeyBinding.new(key: :right,  envelope: :next_tab, display_key: "←/→", description: "Select Tab", help: "Move between tabs")

      # Table navigation
      PREV_PAGE         = KeyBinding.new(key: :h,       envelope: :prev_page,         display_key: "h/l", description: "Prev/Next Page", help: "Use vim keys to move to prev/next page")
      NEXT_PAGE         = KeyBinding.new(key: :l,       envelope: :next_page,         display_key: "h/l", description: "Prev/Next Page", help: "Use vim keys to move to prev/next page")
      ROW_UP            = KeyBinding.new(key: :k,       envelope: :row_up,            display_key: "k/j", description: "Prev/Next Row",  help: "Use vim keys to move to prev/next row")
      ROW_DOWN          = KeyBinding.new(key: :j,       envelope: :row_down,          display_key: "k/j", description: "Prev/Next Row",  help: "Use vim keys to move to prev/next row")
      TOGGLE_SELECT     = KeyBinding.new(key: :x,       envelope: :toggle_select,     display_key: "x",   description: "Select",         help: "Select/deselect current row")
      TOGGLE_SELECT_ALL = KeyBinding.new(key: :shift_A, envelope: :toggle_select_all, display_key: "A",   description: "Select All",     help: "Select/deselect All visible rows")

      # Tab-specific actions
      TERMINATE    = KeyBinding.new(key: :shift_T, envelope: :terminate,    display_key: "T", description: "Terminate", help: "Terminate selected processes")
      QUIET        = KeyBinding.new(key: :shift_Q, envelope: :quiet,        display_key: "Q", description: "Quiet",     help: "Quiet selected processes")
      DELETE_QUEUE = KeyBinding.new(key: :shift_D, envelope: :delete_queue, display_key: "D", description: "Delete",    help: "Delete selected queue")
      TOGGLE_PAUSE = KeyBinding.new(key: :p,       envelope: :toggle_pause, display_key: "p", description: "Pause/Unpause Queue", help: "Pause/Unpause Queue")
      DELETE       = KeyBinding.new(key: :shift_D, envelope: :delete,       display_key: "D", description: "Delete",    help: "Delete selected entries")
      ADD_TO_QUEUE = KeyBinding.new(key: :shift_E, envelope: :add_to_queue, display_key: "E", description: "Enqueue",   help: "Enqueue selected entries")
      RETRY_ENTRY  = KeyBinding.new(key: :shift_R, envelope: :retry,        display_key: "R", description: "Retry",     help: "Retry selected entries")
      KILL         = KeyBinding.new(key: :shift_K, envelope: :kill,         display_key: "K", description: "Kill",      help: "Kill selected entries")
      FILTER       = KeyBinding.new(key: :"/",     envelope: :start_filter, display_key: "/", description: "Filter",    help: "Filter entries")

      # Collections
      GLOBAL = [QUIT, HELP, PREV_TAB, NEXT_TAB].freeze
      TABLE  = [PREV_PAGE, NEXT_PAGE, ROW_UP, ROW_DOWN, TOGGLE_SELECT, TOGGLE_SELECT_ALL].freeze

      FOR_TAB = {
        home: [],
        busy: [TERMINATE, QUIET],
        queues: [DELETE_QUEUE, TOGGLE_PAUSE],
        scheduled: [DELETE, ADD_TO_QUEUE, KILL, FILTER],
        retry: [DELETE, RETRY_ENTRY, KILL, FILTER],
        dead: [DELETE, ADD_TO_QUEUE, FILTER],
        metrics: []
      }.freeze

      def self.controls_for(tab)
        bindings = FOR_TAB[tab]
        return GLOBAL if bindings.empty?

        (GLOBAL + bindings).freeze
      end

      ALL = [
        ESC,
        *FOR_TAB.values.flatten.uniq(&:display_key),
        *GLOBAL
      ].uniq(&:display_key).freeze
    end
  end
end
