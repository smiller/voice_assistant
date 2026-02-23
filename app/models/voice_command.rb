class VoiceCommand < ApplicationRecord
  belongs_to :user

  enum :intent, {
    time_check: "time_check",
    sunset: "sunset",
    timer: "timer",
    reminder: "reminder",
    daily_reminder: "daily_reminder",
    unknown: "unknown"
  }

  enum :status, {
    received: "received",
    processed: "processed",
    scheduled: "scheduled",
    failed: "failed"
  }

  validates :transcript, presence: true
  validates :status, presence: true
end
