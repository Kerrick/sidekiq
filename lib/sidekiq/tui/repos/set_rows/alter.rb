# frozen_string_literal: true

module Sidekiq
  module TUI
    module SetRows
      class Altered < Data.define(:tab, :succeeded_ids)
        include Rooibos::Message::Predicates
      end

      class Alter < Data.define(:set_class_name, :ids, :method_name, :tab)
        include Rooibos::Command::Custom

        def call(out, _token)
          set = Object.const_get(set_class_name).new
          succeeded_ids = []
          ids.each do |id|
            score, jid = id.split("|")
            item = set.fetch(score, jid)&.first
            item&.send(method_name)
            succeeded_ids << id
          end
          out.put(Ractor.make_shareable(Altered.new(tab:, succeeded_ids:)))
        end
      end
    end
  end
end
