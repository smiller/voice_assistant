class LoopingReminderJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :default
  discard_on StandardError

  def perform(looping_reminder_id, scheduled_fire_at)
    loop = LoopingReminder.find_by(id: looping_reminder_id)
    return unless loop&.active?

    audio = ElevenLabsClient.new.synthesize(text: loop.message, voice_id: loop.user.elevenlabs_voice_id)
    token = SecureRandom.hex
    Rails.cache.write("looping_reminder_audio_#{token}", audio, expires_in: 5.minutes)
    Turbo::StreamsChannel.broadcast_append_to(
      loop.user,
      target: "voice_alerts",
      partial: "voice_alerts/alert",
      locals: { token: token }
    )

    next_fire_at = scheduled_fire_at + loop.interval_minutes.minutes
    LoopingReminderJob.set(wait_until: next_fire_at).perform_later(loop.id, next_fire_at)
  end
end
