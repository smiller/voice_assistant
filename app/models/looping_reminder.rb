class LoopingReminder < ApplicationRecord
  belongs_to :user
  has_many :command_aliases, dependent: :destroy

  validates :interval_minutes, numericality: { greater_than_or_equal_to: 1 }
  validates :message, presence: true
  validates :stop_phrase, presence: true
  validates :number, uniqueness: { scope: :user_id }

  scope :active_loops, -> { where(active: true) }

  def activate!
    update!(active: true)
  end

  def stop!
    update!(active: false)
  end

  def self.next_number_for(user)
    (user.looping_reminders.lock.pluck(:number).max || 0) + 1
  end
end
