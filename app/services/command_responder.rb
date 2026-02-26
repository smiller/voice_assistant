class CommandResponder
  include ActionView::RecordIdentifier

  def initialize(tts_client: ElevenLabsClient.new, geo_client: SunriseSunsetClient.new, broadcaster: LoopBroadcaster.new)
    @tts_client = tts_client
    @geo_client = geo_client
    @broadcaster = broadcaster
  end

  def respond(command:, user:)
    text = response_text(command, user)
    schedule_reminder(command, user)
    @tts_client.synthesize(text: text, voice_id: user.elevenlabs_voice_id)
  end

  private

  def response_text(command, user)
    case command[:intent]
    when :time_check, :sunset
      simple_command_text(command[:intent], user)
    when :timer
      timer_text(command[:params][:minutes])
    when :daily_reminder
      daily_reminder_text(command[:params])
    when :reminder
      reminder_response_text(command[:params], user)
    when :create_loop, :run_loop, :stop_loop, :alias_loop, :complete_pending, :give_up
      loop_response_text(command, user)
    else
      unknown_response_text(command)
    end
  end

  def reminder_response_text(params, user)
    time_str = format_time(params[:hour], params[:minute])
    tomorrow = resolve_reminder_time(params, user).to_date > Time.current.in_time_zone(user.timezone).to_date
    "Reminder set for #{time_str}#{' tomorrow' if tomorrow} to #{params[:message]}"
  end

  def loop_response_text(command, user)
    case command[:intent]
    when :create_loop     then handle_create_loop(command[:params], user)
    when :run_loop        then handle_run_loop(command[:params], user)
    when :stop_loop       then handle_stop_loop(command[:params], user)
    when :alias_loop      then handle_alias_loop(command[:params], user)
    when :complete_pending then handle_complete_pending(command[:params], user)
    when :give_up         then "OK, giving up."
    end
  end

  def unknown_response_text(command)
    return "Sorry, I didn't understand that" unless command[:params][:error] == :replacement_phrase_taken

    kind = command[:params][:kind]
    if kind == "alias_phrase_replacement"
      "Alias phrase also already in use. Try another, or say 'give up' to cancel."
    else
      "Stop phrase also already in use. Try another, or say 'give up' to cancel."
    end
  end

  def simple_command_text(intent, user)
    if intent == :time_check
      time = Time.current.in_time_zone(user.timezone)
      "The time is #{time.strftime("%-I:%M %p")}"
    elsif intent == :sunset
      sunset = @geo_client.sunset_time(lat: user.lat, lng: user.lng)
      local = sunset.in_time_zone(user.timezone)
      "Sunset today is at #{local.strftime("%-I:%M %p")}"
    end
  end

  def timer_text(minutes)
    "Timer set for #{minutes} #{"minute".pluralize(minutes)}"
  end

  def daily_reminder_text(params)
    "Daily reminder: #{format_time(params[:hour], params[:minute])} - #{params[:message]}"
  end

  def schedule_reminder(command, user)
    fire_at = case command[:intent]
    when :timer
      command[:params][:minutes].minutes.from_now
    when :reminder, :daily_reminder
      resolve_reminder_time(command[:params], user)
    end
    return unless fire_at

    message = case command[:intent]
    when :timer
      minutes = command[:params][:minutes]
      "Timer finished after #{minutes} #{"minute".pluralize(minutes)}"
    else command[:params][:message]
    end

    recurs = command[:intent] == :daily_reminder
    reminder = Reminder.create!(user: user, kind: command[:intent], message: message, fire_at: fire_at, recurs_daily: recurs)
    ReminderJob.set(wait_until: fire_at).perform_later(reminder.id)

    next_reminder = reminder.next_in_list
    if next_reminder
      Turbo::StreamsChannel.broadcast_before_to(
        reminder.user,
        target: dom_id(next_reminder),
        partial: "reminders/reminder",
        locals: { reminder: reminder }
      )
    else
      target = case reminder.kind
      when "timer"          then "timers"
      when "daily_reminder" then "daily_reminders"
      else                       "reminders"
      end
      Turbo::StreamsChannel.broadcast_append_to(
        reminder.user,
        target: target,
        partial: "reminders/reminder",
        locals: { reminder: reminder }
      )
    end
  end

  def handle_create_loop(params, user)
    if user.phrase_taken?(params[:stop_phrase])
      PendingInteraction.create!(
        user: user,
        kind: "stop_phrase_replacement",
        context: { interval_minutes: params[:interval_minutes], message: params[:message] },
        expires_at: PendingInteraction::INTERACTION_TTL.from_now
      )
      return "Stop phrase already in use. Enter a different stop phrase?"
    end

    create_looping_reminder(
      user: user,
      interval_minutes: params[:interval_minutes],
      message: params[:message],
      stop_phrase: params[:stop_phrase]
    )
  end

  def handle_run_loop(params, user)
    reminder = user.looping_reminders.find_by(number: params[:number])
    return "Loop #{params[:number]} not found" unless reminder

    if reminder.active?
      "Loop #{reminder.number} already active"
    else
      reminder.activate!
      schedule_loop_job(reminder)
      @broadcaster.replace(user, reminder)
      "Running looping reminder #{reminder.number}"
    end
  end

  def handle_stop_loop(params, user)
    reminder = user.looping_reminders.find_by(id: params[:looping_reminder_id])
    return "Looping reminder not found" unless reminder

    reminder.stop!
    @broadcaster.replace(user, reminder)
    "Excellent. Stopping looping reminder #{reminder.number}"
  end

  def handle_alias_loop(params, user)
    reminder = params[:number] && user.looping_reminders.find_by(number: params[:number])
    return "Loop #{params[:number] || '?'} not found" unless reminder

    if user.phrase_taken?(params[:target])
      PendingInteraction.create!(
        user: user,
        kind: "alias_phrase_replacement",
        context: { looping_reminder_id: reminder.id },
        expires_at: PendingInteraction::INTERACTION_TTL.from_now
      )
      return "Alias phrase already in use. Enter a different phrase?"
    end

    create_command_alias(user: user, looping_reminder: reminder, phrase: params[:target])
  end

  def handle_complete_pending(params, user)
    opts = params.with_indifferent_access
    if opts[:kind] == "alias_phrase_replacement"
      reminder = user.looping_reminders.find(opts[:looping_reminder_id])
      create_command_alias(user: user, looping_reminder: reminder, phrase: opts[:replacement_phrase])
    else
      create_looping_reminder(
        user: user,
        interval_minutes: opts[:interval_minutes],
        message: opts[:message],
        stop_phrase: opts[:replacement_phrase]
      )
    end
  end

  def create_looping_reminder(user:, interval_minutes:, message:, stop_phrase:)
    reminder = LoopingReminder.transaction do
      LoopingReminder.create!(
        user: user,
        number: LoopingReminder.next_number_for(user),
        interval_minutes: interval_minutes,
        message: message,
        stop_phrase: stop_phrase,
        active: true
      )
    end
    schedule_loop_job(reminder)
    @broadcaster.append(reminder)
    loop_created_text(reminder)
  end

  def create_command_alias(user:, looping_reminder:, phrase:)
    CommandAlias.create!(user: user, looping_reminder: looping_reminder, phrase: phrase)
    looping_reminder.command_aliases.reload
    @broadcaster.replace(user, looping_reminder)
    "Alias '#{phrase}' created for looping reminder #{looping_reminder.number}"
  end

  def schedule_loop_job(reminder)
    fire_at = reminder.interval_minutes.minutes.from_now
    LoopingReminderJob.set(wait_until: fire_at).perform_later(reminder.id, fire_at, reminder.job_epoch)
  end

  def loop_created_text(reminder)
    mins = reminder.interval_minutes
    "Created looping reminder #{reminder.number}, will ask '#{reminder.message}' every " \
      "#{mins} #{"minute".pluralize(mins)} until you reply '#{reminder.stop_phrase}'"
  end

  def resolve_reminder_time(params, user)
    Time.use_zone(user.timezone) do
      now = Time.current
      time = Time.zone.local(now.year, now.month, now.day, params[:hour], params[:minute])
      time < now ? time + 1.day : time
    end
  end

  def format_time(hour, minute)
    ampm = hour < 12 ? "AM" : "PM"
    display_hour = hour % 12
    display_hour = 12 if display_hour == 0
    minute.zero? ? "#{display_hour} #{ampm}" : format("%d:%02d %s", display_hour, minute, ampm)
  end
end
