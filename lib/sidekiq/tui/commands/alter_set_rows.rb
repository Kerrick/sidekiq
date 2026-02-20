# frozen_string_literal: true

module Sidekiq
  module TUI
    class AlterSetRows < Data.define(:set_class_name, :ids, :action_name, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        set = Object.const_get(set_class_name).new
        ids.each do |id|
          score, jid = id.split("|")
          item = set.fetch(score, jid)&.first
          item&.send(action_name)
        end
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, action: action_name)))
      end
    end
  end
end
