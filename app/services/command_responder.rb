class CommandResponder
  def initialize(tts_client: ElevenLabsClient.new)
    @tts_client = tts_client
  end

  def respond(transcript:, user:)
    command = CommandParser.new.parse(transcript)
    text = response_text(command, user)
    schedule_reminder(command, user, text)
    @tts_client.synthesize(text: text, voice_id: user.elevenlabs_voice_id)
  end

  private

  def response_text(command, user)
    case command[:intent]
    when :time_check
      time = Time.current.in_time_zone(user.timezone)
      "The time is #{time.strftime("%-I:%M %p")}"
    when :sunset
      sunset = SunriseSunsetClient.new.sunset_time(lat: user.lat, lng: user.lng)
      local = sunset.in_time_zone(user.timezone)
      "Sunset today is at #{local.strftime("%-I:%M %p")}"
    when :timer
      minutes = command[:params][:minutes]
      "Timer set for #{minutes} #{"minute".pluralize(minutes)}"
    when :reminder
      p = command[:params]
      time_str = format_time(p[:hour], p[:minute])
      tomorrow = resolve_reminder_time(p, user).to_date > Time.current.in_time_zone(user.timezone).to_date
      "Reminder set for #{time_str}#{' tomorrow' if tomorrow} to #{p[:message]}"
    when :daily_reminder
      p = command[:params]
      time_str = format_time(p[:hour], p[:minute])
      tomorrow = resolve_reminder_time(p, user).to_date > Time.current.in_time_zone(user.timezone).to_date
      "Daily reminder set for #{time_str}#{' tomorrow' if tomorrow} to #{p[:message]}"
    else
      "I didn't understand that"
    end
  end

  def schedule_reminder(command, user, confirmation_text)
    fire_at = case command[:intent]
    when :timer
      command[:params][:minutes].minutes.from_now
    when :reminder, :daily_reminder
      resolve_reminder_time(command[:params], user)
    end
    return unless fire_at

    message = case command[:intent]
    when :timer then confirmation_text
    else command[:params][:message]
    end

    recurs = command[:intent] == :daily_reminder
    reminder = Reminder.create!(user: user, message: message, fire_at: fire_at, recurs_daily: recurs)
    ReminderJob.set(wait_until: fire_at).perform_later(reminder.id)
  end

  def resolve_reminder_time(params, user)
    Time.use_zone(user.timezone) do
      today = Time.current.in_time_zone(user.timezone)
      time = Time.zone.local(today.year, today.month, today.day, params[:hour], params[:minute])
      time.past? ? time + 1.day : time
    end
  end

  def format_time(hour, minute)
    ampm = hour < 12 ? "AM" : "PM"
    display_hour = hour % 12
    display_hour = 12 if display_hour == 0
    format("%d:%02d %s", display_hour, minute, ampm)
  end
end
