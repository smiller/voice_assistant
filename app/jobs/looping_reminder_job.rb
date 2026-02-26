class LoopingReminderJob < ApplicationJob
  queue_as :default
  retry_on ElevenLabsClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(looping_reminder_id, scheduled_fire_at, expected_epoch)
    reminder = LoopingReminder.find_by(id: looping_reminder_id)
    return unless reminder&.active? && reminder.job_epoch == expected_epoch

    audio = ElevenLabsClient.new.synthesize(text: reminder.message, voice_id: reminder.user.elevenlabs_voice_id)
    token = SecureRandom.hex
    Rails.cache.write("voice_alert_#{reminder.user.id}_#{token}", audio, expires_in: 5.minutes)
    Turbo::StreamsChannel.broadcast_append_to(
      reminder.user,
      target: "voice_alerts",
      partial: "voice_alerts/alert",
      locals: { token: token }
    )

    next_fire_at = scheduled_fire_at + reminder.interval_minutes.minutes
    LoopingReminderJob.set(wait_until: next_fire_at).perform_later(reminder.id, next_fire_at, expected_epoch)
  end
end
