class CommandParser
  WORD_TO_NUMBER = {
    "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5,
    "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10,
    "eleven" => 11, "twelve" => 12, "thirteen" => 13, "fourteen" => 14,
    "fifteen" => 15, "twenty" => 20, "thirty" => 30, "forty" => 40,
    "forty-five" => 45, "sixty" => 60
  }.freeze

  REMINDER_TIME_AND_MESSAGE = /(\d{1,2})(?:[: ](\d{2}))?\s*(am|pm)\s+reminder\s+(?:to\s+)?(.+)/i.freeze

  def parse(transcript)
    normalized = normalize_numbers(transcript)

    return { intent: :time_check, params: {} } if normalized.match?(/\btime\b/i)
    return { intent: :sunset, params: {} } if normalized.match?(/\bsunset\b/i)

    if (m = normalized.match(/\btimer\s+(?:for\s+)?(\d+)\s+minute/i))
      return { intent: :timer, params: { minutes: m[1].to_i } }
    end

    if (m = normalized.match(/\bdaily\s+#{REMINDER_TIME_AND_MESSAGE}/))
      return { intent: :daily_reminder, params: reminder_params(m) }
    end

    if (m = normalized.match(/\b#{REMINDER_TIME_AND_MESSAGE}/))
      return { intent: :reminder, params: reminder_params(m) }
    end

    { intent: :unknown, params: {} }
  end

  private

  def reminder_params(match)
    hour   = match[1].to_i
    minute = match[2].to_i
    ampm   = match[3].downcase
    hour  += 12 if ampm == "pm" && hour != 12
    hour   = 0  if ampm == "am" && hour == 12
    { hour:, minute:, message: match[4].strip }
  end

  def normalize_numbers(text)
    WORD_TO_NUMBER.reduce(text) { |t, (word, digit)| t.gsub(/\b#{word}\b/i, digit.to_s) }
  end
end
