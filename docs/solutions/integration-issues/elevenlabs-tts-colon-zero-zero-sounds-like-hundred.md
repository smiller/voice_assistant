---
title: "ElevenLabs TTS: ':00' in Time Strings Reads as 'Hundred' — Omit When Minutes Are Zero"
date: 2026-02-24
problem_type: integration-issue
component: elevenlabs_tts
tags:
  - elevenlabs
  - tts
  - text-to-speech
  - time-formatting
  - naturalness
  - command-responder
  - reminder-job
symptoms:
  - "ElevenLabs reads '9:00 PM' as 'nine hundred PM'"
  - "Time confirmations sound robotic and unnatural"
  - "On-the-hour reminder deliveries say 'nine hundred AM' instead of 'nine AM'"
  - "Voice assistant confirmation sounds wrong for whole-hour reminder times"
affected_files:
  - app/services/command_responder.rb
  - app/jobs/reminder_job.rb
  - spec/services/command_responder_spec.rb
  - spec/jobs/reminder_job_spec.rb
  - spec/integration/voice_command_round_trip_spec.rb
related_specs:
  - spec/services/command_responder_spec.rb
  - spec/jobs/reminder_job_spec.rb
  - spec/integration/voice_command_round_trip_spec.rb
---

# ElevenLabs TTS: ':00' in Time Strings Reads as 'Hundred' — Omit When Minutes Are Zero

## Problem Symptom

Setting a reminder for "9 PM" caused the voice assistant to respond with **"Reminder set for nine hundred PM to take medication"** instead of the expected "Reminder set for nine PM to take medication."

Similarly, when a daily reminder fired at 7 AM, the synthesized audio said **"It's seven hundred AM. Reminder: write morning pages"** rather than "It's seven AM."

## Root Cause

`CommandResponder#format_time` used `strftime`-style formatting that always included the minute component:

```ruby
def format_time(hour, minute)
  ampm = hour < 12 ? "AM" : "PM"
  display_hour = hour % 12
  display_hour = 12 if display_hour == 0
  format("%d:%02d %s", display_hour, minute, ampm)   # always ":00"
end
```

For a 9 PM reminder, this produced `"9:00 PM"`. ElevenLabs — like many TTS engines — reads `"9:00"` as a ratio or clock time using its numeral parser, which interprets `"9:00"` as `"nine hundred"` (the same way "9:00" in a sports score context is read). The `:00` is the trigger.

`ReminderJob#delivery_text` had the same issue:

```ruby
current_time = Time.current.in_time_zone(reminder.user.timezone).strftime("%-I:%M %p")
"It's #{current_time}. Reminder: #{reminder.message}"
```

`strftime("%-I:%M %p")` always emits the `:MM` component, so "7:00 AM" was always passed to ElevenLabs.

## Working Solution

### `app/services/command_responder.rb`

**Before:**

```ruby
def format_time(hour, minute)
  ampm = hour < 12 ? "AM" : "PM"
  display_hour = hour % 12
  display_hour = 12 if display_hour == 0
  format("%d:%02d %s", display_hour, minute, ampm)
end
```

**After:**

```ruby
def format_time(hour, minute)
  ampm = hour < 12 ? "AM" : "PM"
  display_hour = hour % 12
  display_hour = 12 if display_hour == 0
  minute.zero? ? "#{display_hour} #{ampm}" : format("%d:%02d %s", display_hour, minute, ampm)
end
```

### `app/jobs/reminder_job.rb`

**Before:**

```ruby
current_time = Time.current.in_time_zone(reminder.user.timezone).strftime("%-I:%M %p")
"It's #{current_time}. Reminder: #{reminder.message}"
```

**After:**

```ruby
time = Time.current.in_time_zone(reminder.user.timezone)
current_time = time.min.zero? ? time.strftime("%-I %p") : time.strftime("%-I:%M %p")
"It's #{current_time}. Reminder: #{reminder.message}"
```

The fix in both cases: when minutes are zero, omit the colon-and-minutes entirely. `"9 PM"` reads as "nine PM". Non-zero minutes (e.g. `"9:30 PM"`) are unchanged — `"9:30"` reads correctly as "nine thirty".

### Tests updated

All spec assertions that expected `"9:00 PM"` (or similar) were updated to expect `"9 PM"`. A new positive test was added in each spec to confirm non-zero minutes still include the colon:

**`spec/services/command_responder_spec.rb`:**

```ruby
context "with a reminder at a non-zero minute" do
  it "includes the minutes in the confirmation text" do
    travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
      responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 30, message: "check in" } }, user: user)

      expect(tts_client).to have_received(:synthesize)
        .with(text: "Reminder set for 9:30 PM to check in", voice_id: "voice123")
    end
  end
end
```

**`spec/jobs/reminder_job_spec.rb`:**

```ruby
it "includes minutes in the synthesized text when fired at a non-zero minute" do
  travel_to Time.new(2026, 2, 23, 21, 30, 0, "UTC") do  # 4:30 PM ET
    described_class.perform_now(reminder.id)

    expect(tts_client).to have_received(:synthesize)
      .with(text: "It's 4:30 PM. Reminder: take medication", voice_id: "voice123")
  end
end
```

## Key Insight

**TTS engines parse numbers using natural-language heuristics, not display conventions.** `"9:00"` looks like a clock time to humans and reads cleanly when spoken aloud by a human. But ElevenLabs (and similar engines) parse it via numeral-ratio heuristics: `"9:00"` → "nine hundred", the same pattern as sports scores or military time.

The fix is to produce text that sounds natural when read aloud, not text that looks correct on screen. `"9 PM"` and `"9:30 PM"` are both visually correct and phonetically unambiguous. `"9:00 PM"` is visually correct but phonetically wrong.

**Rule of thumb:** When generating text for TTS, treat the input as prose to be read aloud. Avoid numeric patterns that have ambiguous spoken interpretations (`:00`, currency symbols, abbreviations without spaces).

---

## Prevention & Best Practices

### Always test TTS strings for naturalness

Add an explicit test for zero-minute times whenever time formatting is involved. The failure mode is silent from an automated-testing perspective (the spec passes, the audio is wrong), making it easy to miss.

### Omit `:MM` when minutes are zero — for both display and TTS

This matches natural English: people say "nine PM", not "nine oh-oh PM". The colon-zero-zero pattern is a clock-display convention that does not translate to spoken language.

### Use `strftime("%-I %p")` for zero-minute times

`%-I` omits the leading zero (9, not 09). Combine with a space and `%p` for AM/PM:

```ruby
time.min.zero? ? time.strftime("%-I %p") : time.strftime("%-I:%M %p")
```

### Apply the same fix everywhere a time is synthesized

Both the confirmation response (`CommandResponder#format_time`) and the delivery notification (`ReminderJob#delivery_text`) had the same bug. When you find this class of issue in one place, search the entire codebase for related synthesis calls.

### Pitfalls to avoid

| Pitfall | Problem | Fix |
|---------|---------|-----|
| `"%-I:%M %p"` for all times | `"9:00 PM"` → ElevenLabs says "nine hundred PM" | Omit `:MM` when `min.zero?` |
| `strftime` always includes minutes | Zero-minute times always have `:00` | Conditional format based on `min.zero?` |
| Testing only non-zero minute times | Zero-minute bug goes undetected | Always test both `minute: 0` and `minute: 30` |
| Fixing only the confirmation text | Delivery notification still says "hundred" | Search for all `strftime` / format calls that produce times for synthesis |

---

## Sources & References

### Related project documents

- **`docs/plans/2026-02-23-feat-voice-assistant-rails-app-plan.md`** — Architecture showing `ElevenLabsClient#synthesize` and the two places time strings are generated
- **`docs/solutions/integration-issues/empty-webm-audio-deepgram-400-corrupt-data.md`** — Related: audio pipeline integration issues

### ElevenLabs behavior

ElevenLabs uses SSML-style text normalization. The `:00` pattern triggers its clock/ratio parser. To force spoken hour-only time, the simplest fix is textual (omit `:00`) rather than SSML markup — textual fixes are more portable across TTS providers.
