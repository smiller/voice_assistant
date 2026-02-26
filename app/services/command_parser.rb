class CommandParser
  WORD_TO_NUMBER = {
    "oh" => 0, "zero" => 0,
    "one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5,
    "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10,
    "eleven" => 11, "twelve" => 12, "thirteen" => 13, "fourteen" => 14,
    "fifteen" => 15, "sixteen" => 16, "seventeen" => 17, "eighteen" => 18,
    "nineteen" => 19, "twenty" => 20, "thirty" => 30, "forty" => 40,
    "forty-five" => 45, "fifty" => 50, "sixty" => 60
  }.freeze

  REMINDER_TIME_AND_MESSAGE    = /(\d{1,2})(?:[: ](\d{1,2}))?\s*(am|pm)\s+reminder\s+(?:to\s+)?(.+)/i.freeze
  REMINDER_AT_TIME_AND_MESSAGE  = /reminder\s+at\s+(\d{1,2})(?:[: ](\d{1,2}))?\s*(am|pm)\s+(?:to\s+)?(.+)/i.freeze
  REMINDER_FOR_TIME_AND_MESSAGE = /reminder\s+for\s+(\d{1,2})(?:[: ](\d{1,2}))?\s*(am|pm)\s+(?:to\s+)?(.+)/i.freeze

  def parse(transcript)
    normalized = normalize_numbers(transcript)

    return { intent: :time_check, params: {} } if normalized.match?(/\btime\b/i)
    return { intent: :sunset, params: {} }     if normalized.match?(/\bsunset\b/i)

    if (m = normalized.match(/\btimer\s+(?:for\s+)?(\d+)\s+minute/i))
      return { intent: :timer, params: { minutes: m[1].to_i } }
    end

    if (m = normalized.match(/\blooping\s+reminder\s+for\s+(\d+)\s+minutes?\s+saying\s+'([^']+)'\s+until\s+I\s+say\s+'([^']+)'/i))
      return { intent: :create_loop,
               params: { interval_minutes: m[1].to_i, message: m[2].strip, stop_phrase: m[3].strip } }
    end

    if (m = normalized.match(/\balias\s+'([^']+)'\s+as\s+'([^']+)'/i))
      return { intent: :alias_loop, params: { source: m[1].strip, target: m[2].strip } }
    end

    if (m = normalized.match(/\brun\s+(?:loop|looping\s+reminder)\s+(\d+)/i))
      return { intent: :run_loop, params: { number: m[1].to_i } }
    end

    if (m = daily_reminder_match(normalized))
      return { intent: :daily_reminder, params: reminder_params(m) }
    end

    if (m = reminder_match(normalized))
      return { intent: :reminder, params: reminder_params(m) }
    end

    { intent: :unknown, params: {} }
  end

  private

  def daily_reminder_match(normalized)
    normalized.match(/\bdaily\s+#{REMINDER_TIME_AND_MESSAGE}/) ||
      normalized.match(/\bdaily\s+#{REMINDER_AT_TIME_AND_MESSAGE}/) ||
      normalized.match(/\bdaily\s+#{REMINDER_FOR_TIME_AND_MESSAGE}/)
  end

  def reminder_match(normalized)
    normalized.match(/\b#{REMINDER_TIME_AND_MESSAGE}/) ||
      normalized.match(/\b#{REMINDER_AT_TIME_AND_MESSAGE}/) ||
      normalized.match(/\b#{REMINDER_FOR_TIME_AND_MESSAGE}/)
  end

  def reminder_params(match)
    hour   = match[1].to_i
    minute = match[2].to_i
    ampm   = match[3].downcase
    hour  += 12 if ampm == "pm" && hour != 12
    hour   = 0  if ampm == "am" && hour == 12
    { hour:, minute:, message: match[4].strip }
  end

  def normalize_numbers(text)
    words_replaced = WORD_TO_NUMBER.reduce(text) { |t, (word, digit)| t.gsub(/\b#{word}\b/i, digit.to_s) }
    # "oh/zero" prefix collapses "0 5" -> "05" (e.g. "six oh five" -> "6 05")
    oh_collapsed    = words_replaced.gsub(/\b0 ([1-9])\b/) { "0#{$1}" }
    # Tens+ones pairs collapse "40 9" -> "49" (e.g. "six forty nine" -> "6 49").
    # Ambiguity policy: bare single-digit after hour ("six five") is treated as
    # the minute value directly (5), i.e. 6:05 not 6:50. "Six fifty" is unambiguous.
    oh_collapsed.gsub(/\b([1-5]0) ([1-9])\b/) { ($1.to_i + $2.to_i).to_s }
  end
end
