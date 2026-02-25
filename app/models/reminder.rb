class Reminder < ApplicationRecord
  belongs_to :user

  enum :kind, {
    reminder: "reminder",
    daily_reminder: "daily_reminder",
    timer: "timer"
  }

  enum :status, {
    pending: "pending",
    delivered: "delivered",
    cancelled: "cancelled"
  }

  validates :message, presence: true
  validates :fire_at, presence: true
  validates :recurs_daily, inclusion: { in: [ true ] }, if: :daily_reminder?
  validates :recurs_daily, inclusion: { in: [ false ] }, unless: :daily_reminder?

  def day_label
    return nil if daily_reminder?

    local_date = fire_at.in_time_zone(user.timezone).to_date
    today      = Time.current.in_time_zone(user.timezone).to_date

    case local_date
    when today     then "today"
    when today + 1 then "tomorrow"
    else                local_date.strftime("%b %-d")
    end
  end

  def next_in_list
    siblings = user.reminders.pending.where("fire_at > ?", Time.current).where.not(id: id).public_send(kind)

    if daily_reminder?
      my_minutes = time_of_day_minutes(fire_at)
      siblings.sort_by { |r| time_of_day_minutes(r.fire_at) }
              .find { |r| time_of_day_minutes(r.fire_at) > my_minutes }
    else
      siblings.order(:fire_at).where("fire_at > ?", fire_at).first
    end
  end

  private

  def time_of_day_minutes(timestamp)
    local = timestamp.in_time_zone(user.timezone)
    local.hour * 60 + local.min
  end
end
