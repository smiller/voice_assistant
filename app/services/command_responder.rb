class CommandResponder
  def initialize(tts_client: ElevenLabsClient.new)
    @tts_client = tts_client
  end

  def respond(transcript:, user:)
    command = CommandParser.new.parse(transcript)
    text = response_text(command, user)
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
      "Timer set for #{minutes} minutes"
    when :reminder
      p = command[:params]
      time_str = format_time(p[:hour], p[:minute])
      "Reminder set for #{time_str} to #{p[:message]}"
    when :daily_reminder
      p = command[:params]
      time_str = format_time(p[:hour], p[:minute])
      "Daily reminder set for #{time_str} to #{p[:message]}"
    else
      "I didn't understand that"
    end
  end

  def format_time(hour, minute)
    ampm = hour < 12 ? "AM" : "PM"
    display_hour = hour % 12
    display_hour = 12 if display_hour == 0
    format("%d:%02d %s", display_hour, minute, ampm)
  end
end
