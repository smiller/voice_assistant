class CommandResponder
  include ActionView::RecordIdentifier

  def initialize(tts_client: ElevenLabsClient.new, geo_client: SunriseSunsetClient.new)
    @tts_client = tts_client
    @geo_client = geo_client
  end

  def respond(command:, user:)
    text = response_text(command, user)
    schedule_reminder(command, user)
    @tts_client.synthesize(text: text, voice_id: user.elevenlabs_voice_id)
  end

  private

  def response_text(command, user)
    case command[:intent]
    when :time_check
      time = Time.current.in_time_zone(user.timezone)
      "The time is #{time.strftime("%-I:%M %p")}"
    when :sunset
      sunset = @geo_client.sunset_time(lat: user.lat, lng: user.lng)
      local = sunset.in_time_zone(user.timezone)
      "Sunset today is at #{local.strftime("%-I:%M %p")}"
    when :timer
      minutes = command[:params][:minutes]
      "Timer set for #{minutes} #{"minute".pluralize(minutes)}"
    when :daily_reminder
      params = command[:params]
      "Daily reminder: #{format_time(params[:hour], params[:minute])} - #{params[:message]}"
    when :reminder
      params = command[:params]
      time_str = format_time(params[:hour], params[:minute])
      tomorrow = resolve_reminder_time(params, user).to_date > Time.current.in_time_zone(user.timezone).to_date
      "Reminder set for #{time_str}#{' tomorrow' if tomorrow} to #{params[:message]}"
    when :create_loop
      handle_create_loop(command[:params], user)
    when :run_loop
      handle_run_loop(command[:params], user)
    when :stop_loop
      handle_stop_loop(command[:params], user)
    when :alias_loop
      handle_alias_loop(command[:params], user)
    when :complete_pending
      handle_complete_pending(command[:params], user)
    when :give_up
      "OK, giving up."
    else
      if command[:params][:error] == :replacement_phrase_taken
        kind = command[:params][:kind]
        if kind == "alias_phrase_replacement"
          "Alias phrase also already in use. Try another, or say 'give up' to cancel."
        else
          "Stop phrase also already in use. Try another, or say 'give up' to cancel."
        end
      else
        "Sorry, I didn't understand that"
      end
    end
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
    if phrase_taken_for_user?(params[:stop_phrase], user)
      PendingInteraction.create!(
        user: user,
        kind: "stop_phrase_replacement",
        context: { interval_minutes: params[:interval_minutes], message: params[:message] },
        expires_at: 5.minutes.from_now
      )
      return "Stop phrase already in use. Enter a different stop phrase?"
    end

    loop = LoopingReminder.create!(
      user: user,
      number: LoopingReminder.next_number_for(user),
      interval_minutes: params[:interval_minutes],
      message: params[:message],
      stop_phrase: params[:stop_phrase],
      active: true
    )
    schedule_loop_job(loop)
    broadcast_loop_append(loop)
    loop_created_text(loop)
  end

  def handle_run_loop(params, user)
    loop = user.looping_reminders.find_by(number: params[:number])
    return "Loop #{params[:number]} not found" unless loop

    if loop.active?
      "Loop #{loop.number} already active"
    else
      loop.activate!
      schedule_loop_job(loop)
      Turbo::StreamsChannel.broadcast_replace_to(
        user,
        target: dom_id(loop),
        partial: "looping_reminders/looping_reminder",
        locals: { looping_reminder: loop }
      )
      "Running looping reminder #{loop.number}"
    end
  end

  def handle_stop_loop(params, user)
    loop = user.looping_reminders.find(params[:looping_reminder_id])
    loop.stop!
    Turbo::StreamsChannel.broadcast_replace_to(
      user,
      target: dom_id(loop),
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: loop }
    )
    "Excellent. Stopping looping reminder #{loop.number}"
  end

  def handle_alias_loop(params, user)
    number = params[:source].match(/\brun\s+(?:loop|looping\s+reminder)\s+(\d+)/i)&.then { |m| m[1].to_i }
    loop = number && user.looping_reminders.find_by(number: number)
    return "Loop #{number || '?'} not found" unless loop

    if phrase_taken_for_user?(params[:target], user)
      PendingInteraction.create!(
        user: user,
        kind: "alias_phrase_replacement",
        context: { looping_reminder_id: loop.id },
        expires_at: 5.minutes.from_now
      )
      return "Alias phrase already in use. Enter a different phrase?"
    end

    CommandAlias.create!(user: user, looping_reminder: loop, phrase: params[:target])
    Turbo::StreamsChannel.broadcast_replace_to(
      user,
      target: dom_id(loop),
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: loop }
    )
    "Alias '#{params[:target]}' created for looping reminder #{loop.number}"
  end

  def handle_complete_pending(params, user)
    p = params.with_indifferent_access
    if p[:kind] == "alias_phrase_replacement"
      loop = user.looping_reminders.find(p[:looping_reminder_id])
      CommandAlias.create!(user: user, looping_reminder: loop, phrase: p[:replacement_phrase])
      Turbo::StreamsChannel.broadcast_replace_to(
        user,
        target: dom_id(loop),
        partial: "looping_reminders/looping_reminder",
        locals: { looping_reminder: loop }
      )
      "Alias '#{p[:replacement_phrase]}' created for looping reminder #{loop.number}"
    else
      loop = LoopingReminder.create!(
        user: user,
        number: LoopingReminder.next_number_for(user),
        interval_minutes: p[:interval_minutes],
        message: p[:message],
        stop_phrase: p[:replacement_phrase],
        active: true
      )
      schedule_loop_job(loop)
      broadcast_loop_append(loop)
      loop_created_text(loop)
    end
  end

  def schedule_loop_job(loop)
    fire_at = loop.interval_minutes.minutes.from_now
    LoopingReminderJob.set(wait_until: fire_at).perform_later(loop.id, fire_at)
  end

  def broadcast_loop_append(loop)
    Turbo::StreamsChannel.broadcast_append_to(
      loop.user,
      target: "looping_reminders",
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: loop }
    )
  end

  def loop_created_text(loop)
    mins = loop.interval_minutes
    "Created looping reminder #{loop.number}, will ask '#{loop.message}' every " \
      "#{mins} #{"minute".pluralize(mins)} until you reply '#{loop.stop_phrase}'"
  end

  def phrase_taken_for_user?(phrase, user)
    user.looping_reminders.where("LOWER(stop_phrase) = ?", phrase.downcase).exists? ||
      user.command_aliases.where("LOWER(phrase) = ?", phrase.downcase).exists?
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
