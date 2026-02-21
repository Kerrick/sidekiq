#!/usr/bin/env ruby
# frozen_string_literal: true

# Seeds Sidekiq with test data for TUI development.
# Usage: bundle exec ruby bin/seed_tui_data.rb

require "bundler/setup"
require "sidekiq"
require "sidekiq/api"

puts "Seeding Sidekiq with test data..."

# Clear existing test data
Sidekiq::ScheduledSet.new.clear
Sidekiq::RetrySet.new.clear
Sidekiq::DeadSet.new.clear
Sidekiq::Queue.all.each(&:clear)

# Helper to push jobs directly into sorted sets
def push_to_set(set_class, count, base_time: Time.now)
  conn = Sidekiq.redis { |c| c }
  count.times do |i|
    job = {
      "class" => ["HardWorker", "EmailWorker", "ReportGenerator", "DataImporter", "NotificationSender"].sample,
      "args" => [[i, "arg_#{rand(1000)}"], [{"user_id" => rand(100)}], [rand(50), "batch"]].sample,
      "queue" => ["default", "critical", "low", "mailers", "reports"].sample,
      "jid" => SecureRandom.hex(12),
      "created_at" => base_time.to_f,
      "enqueued_at" => base_time.to_f,
      "retry" => true
    }

    score = (base_time + rand(-86400..86400)).to_f

    case set_class
    when :scheduled
      Sidekiq.redis { |c| c.call("ZADD", "schedule", score.to_s, Sidekiq.dump_json(job)) }
    when :retry
      job["retry_count"] = rand(1..5)
      job["error_message"] = ["Connection timeout", "Record not found", "Rate limit exceeded", "Invalid argument"].sample
      job["error_class"] = ["Redis::TimeoutError", "ActiveRecord::RecordNotFound", "RateLimitError", "ArgumentError"].sample
      job["failed_at"] = (base_time - rand(3600)).to_f
      Sidekiq.redis { |c| c.call("ZADD", "retry", score.to_s, Sidekiq.dump_json(job)) }
    when :dead
      job["retry_count"] = 25
      job["error_message"] = ["Max retries exceeded", "Fatal error", "Service unavailable"].sample
      job["error_class"] = ["RuntimeError", "StandardError", "Sidekiq::Shutdown"].sample
      job["failed_at"] = (base_time - rand(86400)).to_f
      Sidekiq.redis { |c| c.call("ZADD", "dead", score.to_s, Sidekiq.dump_json(job)) }
    end
  end
end

# Seed queues with some jobs
%w[default critical low mailers reports].each do |queue_name|
  rand(5..20).times do |i|
    Sidekiq::Client.push(
      "class" => "HardWorker",
      "args" => [i, rand(100)],
      "queue" => queue_name
    )
  end
end

# Seed sorted sets
push_to_set(:scheduled, 125)
push_to_set(:retry, 125)
push_to_set(:dead, 125)

puts "Done!"
puts "  Queues: #{Sidekiq::Queue.all.map { |q| "#{q.name}(#{q.size})" }.join(", ")}"
puts "  Scheduled: #{Sidekiq::ScheduledSet.new.size}"
puts "  Retries: #{Sidekiq::RetrySet.new.size}"
puts "  Dead: #{Sidekiq::DeadSet.new.size}"
puts
puts "Now run: bundle exec bin/tui"
