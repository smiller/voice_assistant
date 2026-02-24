class CommandResponder
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
    when :reminder, :daily_reminder
      params = command[:params]
      time_str = format_time(params[:hour], params[:minute])
      tomorrow = resolve_reminder_time(params, user).to_date > Time.current.in_time_zone(user.timezone).to_date
      prefix = command[:intent] == :daily_reminder ? "Daily reminder" : "Reminder"
      "#{prefix} set for #{time_str}#{' tomorrow' if tomorrow} to #{params[:message]}"
    else
      "Sorry, I didn't understand that"
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
    format("%d:%02d %s", display_hour, minute, ampm)
  end
end
