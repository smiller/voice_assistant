class LoopingReminderDispatcher
  def dispatch(transcript:, user:)
    clean_expired_interactions(user)

    pending = PendingInteraction.for(user)
    return handle_pending_interaction(pending, transcript, user) if pending

    if (reminder = match_stop_phrase(transcript, user))
      return { intent: :stop_loop, params: { looping_reminder_id: reminder.id } }
    end

    if (al = match_alias(transcript, user))
      return { intent: :run_loop, params: { number: al.looping_reminder.number } }
    end

    CommandParser.new.parse(transcript)
  end

  private

  def clean_expired_interactions(user)
    user.pending_interactions.where("expires_at <= ?", Time.current).destroy_all
  end

  def match_stop_phrase(transcript, user)
    user.looping_reminders.active_loops.find do |lr|
      transcript.downcase.include?(lr.stop_phrase.downcase)
    end
  end

  def match_alias(transcript, user)
    user.command_aliases
        .includes(:looping_reminder)
        .where("LOWER(phrase) = ?", transcript.strip.downcase)
        .first
  end

  def handle_pending_interaction(pending, transcript, user)
    phrase = transcript.strip

    if phrase.casecmp?("give up")
      pending.destroy
      return { intent: :give_up, params: {} }
    end

    if user.phrase_taken?(phrase)
      pending.update!(expires_at: 5.minutes.from_now)
      return { intent: :unknown,
               params: { error: :replacement_phrase_taken, kind: pending.kind } }
    end

    context = pending.context.with_indifferent_access
    pending.destroy
    { intent: :complete_pending,
      params: context.merge(replacement_phrase: phrase, kind: pending.kind) }
  end
end
