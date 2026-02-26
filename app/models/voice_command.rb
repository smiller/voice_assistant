class VoiceCommand < ApplicationRecord
  belongs_to :user

  enum :intent, {
    time_check:     "time_check",
    sunset:         "sunset",
    timer:          "timer",
    reminder:       "reminder",
    daily_reminder: "daily_reminder",
    create_loop:    "create_loop",
    run_loop:       "run_loop",
    alias_loop:     "alias_loop",
    stop_loop:      "stop_loop",
    give_up:        "give_up",
    unknown:        "unknown"
  }

  enum :status, {
    received: "received",
    processed: "processed"
  }

  validates :transcript, presence: true
  validates :status, presence: true
end
