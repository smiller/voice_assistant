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
    Turbo::StreamsChannel.broadcast_append_to(
      reminder.user,
      target: "looping_reminders",
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: reminder }
    )
  end
end
