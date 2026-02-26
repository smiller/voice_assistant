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
    next_reminder = reminder.user.looping_reminders
                             .where("number > ?", reminder.number)
                             .order(:number).first

    if next_reminder
      Turbo::StreamsChannel.broadcast_before_to(
        reminder.user,
        target: dom_id(next_reminder),
        partial: "looping_reminders/looping_reminder",
        locals: { looping_reminder: reminder }
      )
    else
      Turbo::StreamsChannel.broadcast_append_to(
        reminder.user,
        target: "looping_reminders",
        partial: "looping_reminders/looping_reminder",
        locals: { looping_reminder: reminder }
      )
    end
  end
end
