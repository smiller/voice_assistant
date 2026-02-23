class Reminder < ApplicationRecord
  belongs_to :user
  belongs_to :voice_command, optional: true

  enum :status, {
    pending: "pending",
    delivered: "delivered",
    cancelled: "cancelled"
  }

  validates :message, presence: true
  validates :fire_at, presence: true
end
