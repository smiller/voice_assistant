class LoopBroadcaster
  include ActionView::RecordIdentifier

  def replace(user, reminder)
    Turbo::StreamsChannel.broadcast_replace_to(
      user,
      target: dom_id(reminder),
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: reminder }
    )
  end

  def append(reminder)
    Rails.logger.info("[LoopBroadcaster] appending reminder #{reminder.id} to stream for user #{reminder.user_id}")
    Turbo::StreamsChannel.broadcast_append_to(
      reminder.user,
      target: "looping_reminders",
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: reminder }
    )
    Rails.logger.info("[LoopBroadcaster] broadcast_append_to complete for reminder #{reminder.id}")
  end
end
