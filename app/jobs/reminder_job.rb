class ReminderJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :default
  discard_on StandardError

  def perform(reminder_id)
    reminder = Reminder.find_by(id: reminder_id)
    return unless reminder&.pending?

    audio = ElevenLabsClient.new.synthesize(text: delivery_text(reminder), voice_id: reminder.user.elevenlabs_voice_id)
    token = SecureRandom.hex
    Rails.cache.write("voice_alert_#{reminder.user.id}_#{token}", audio, expires_in: 5.minutes)
    Turbo::StreamsChannel.broadcast_append_to(
      reminder.user,
      target: "voice_alerts",
      partial: "voice_alerts/alert",
      locals: { token: token }
    )
    reminder.delivered!
    Turbo::StreamsChannel.broadcast_remove_to(reminder.user, target: dom_id(reminder))

    return unless reminder.recurs_daily?

    next_fire_at = reminder.fire_at + 1.day
    new_reminder = Reminder.create!(
      user: reminder.user, kind: reminder.kind, message: reminder.message,
      fire_at: next_fire_at, recurs_daily: true
    )
    ReminderJob.set(wait_until: next_fire_at).perform_later(new_reminder.id)

    next_sibling = new_reminder.next_in_list
    if next_sibling
      Turbo::StreamsChannel.broadcast_before_to(
        new_reminder.user,
        target: dom_id(next_sibling),
        partial: "reminders/reminder",
        locals: { reminder: new_reminder }
      )
    else
      Turbo::StreamsChannel.broadcast_append_to(
        new_reminder.user,
        target: "daily_reminders",
        partial: "reminders/reminder",
        locals: { reminder: new_reminder }
      )
    end
  end

  private

  def delivery_text(reminder)
    return reminder.message if reminder.timer?

    time = Time.current.in_time_zone(reminder.user.timezone)
    current_time = time.min.zero? ? time.strftime("%-I %p") : time.strftime("%-I:%M %p")
    "It's #{current_time}. Reminder: #{reminder.message}"
  end
end
