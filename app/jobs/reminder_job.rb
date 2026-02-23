class ReminderJob < ApplicationJob
  queue_as :default

  def perform(reminder_id)
    reminder = Reminder.find_by(id: reminder_id)
    return unless reminder&.pending?

    audio = ElevenLabsClient.new.synthesize(text: reminder.message, voice_id: reminder.user.elevenlabs_voice_id)
    token = SecureRandom.hex
    Rails.cache.write("reminder_audio_#{token}", audio)
    Turbo::StreamsChannel.broadcast_append_to(
      reminder.user,
      target: "voice_alerts",
      partial: "voice_alerts/alert",
      locals: { token: token }
    )
    reminder.delivered!

    return unless reminder.recurs_daily?

    next_fire_at = reminder.fire_at + 1.day
    new_reminder = Reminder.create!(
      user: reminder.user, message: reminder.message,
      fire_at: next_fire_at, recurs_daily: true
    )
    ReminderJob.set(wait_until: next_fire_at).perform_later(new_reminder.id)
  end
end
