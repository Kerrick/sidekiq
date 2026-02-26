# frozen_string_literal: true

module Sidekiq
  module TUI
    class AlterSetRows < Data.define(:set_class_name, :ids, :method_name, :envelope, :tab)
      include Rooibos::Command::Custom

      def call(out, _token)
        DebugLogger.info("AlterSetRows: set=#{set_class_name} method=#{method_name} ids=#{ids.inspect}")
        set = Object.const_get(set_class_name).new
        succeeded_ids = []
        ids.each do |id|
          score, jid = id.split('|')
          DebugLogger.info("AlterSetRows: fetching score=#{score} jid=#{jid}")
          item = set.fetch(score, jid)&.first
          DebugLogger.info("AlterSetRows: item=#{item.class} found=#{!item.nil?}")
          item&.send(method_name)
          succeeded_ids << id
        rescue StandardError => e
          DebugLogger.info("AlterSetRows: failed on #{id}: #{e.message}")
          break
        end
        out.put(Ractor.make_shareable(ActionComplete.new(tab:, envelope:, succeeded_ids:)))
      end
    end
  end
end
