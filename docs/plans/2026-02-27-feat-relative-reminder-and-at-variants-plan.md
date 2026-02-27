---
title: "feat: Add 'reminder in N minutes' command and document 'set a reminder at' variants"
type: feat
status: completed
date: 2026-02-27
---

# feat: Add 'reminder in N minutes' command and document 'set a reminder at' variants

## Overview

Three related additions:

1. **New command** — `"set a reminder in 20 minutes to take the food out of the oven"` fires a one-shot reminder N minutes from now.
2. **Existing-but-undocumented forms** — `"set a reminder at 9pm to take medication"` and `"set a daily reminder at 9pm to take medication"` already parse correctly (the `\b` word boundary handles the article "a") but lack explicit tests and are absent from the README and home page.
3. **README + home page** — update both to reflect all three additions.

---

## Proposed Implementation

### 1. `CommandParser` — new intent `:relative_reminder`

Add a private `relative_reminder_command` method and call it in the `parse` chain between `loop_command` and `scheduled_reminder_command`:

```ruby
# app/services/command_parser.rb

def parse(transcript)
  normalized = normalize_numbers(transcript)

  simple_command(normalized)                   ||
    timer_command(normalized)                  ||
    loop_command(normalized)                   ||
    relative_reminder_command(normalized)      ||   # ← new
    scheduled_reminder_command(normalized)     ||
    unrecognized_command
end

def relative_reminder_command(normalized)
  return unless (m = normalized.match(/\breminder\s+in\s+(\d+)\s+minutes?\s+(?:to\s+)?(.+)/i))

  { intent: :relative_reminder, params: { minutes: m[1].to_i, message: m[2].strip } }
end
```

**Regex notes:**
- `minutes?` handles both "minute" and "minutes" (singular/plural from STT)
- `(?:to\s+)?` makes the linking word optional — Deepgram may or may not produce it
- `.strip` on the message mirrors the existing reminder pattern
- No `\z` anchor needed because the message is greedy and `.strip` handles trailing whitespace
- Number-word normalisation runs first (`normalize_numbers`), so "twenty" → "20" before matching

**Ordering:** `relative_reminder_command` must come before `scheduled_reminder_command`. The scheduled reminder regexes require `am|pm`, so there is no overlap risk, but positioning near related intent is cleaner.

---

### 2. `CommandResponder` — response text and scheduling

**`response_text`** — add `:relative_reminder` branch:

```ruby
# app/services/command_responder.rb

when :relative_reminder
  relative_reminder_text(command[:params][:minutes])

# ...

def relative_reminder_text(minutes)
  "Reminder set for #{minutes} #{"minute".pluralize(minutes)} from now"
end
```

**`schedule_reminder`** — add `:relative_reminder` to the `fire_at` case, and store `kind: :reminder` explicitly (`:relative_reminder` is not a valid enum value on `Reminder`):

```ruby
def schedule_reminder(command, user)
  fire_at = case command[:intent]
  when :timer, :relative_reminder
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

  # :relative_reminder stores as kind :reminder — same delivery path, fire_at differs
  kind = command[:intent] == :relative_reminder ? :reminder : command[:intent]
  recurs = command[:intent] == :daily_reminder
  reminder = Reminder.create!(user: user, kind: kind, message: message, fire_at: fire_at, recurs_daily: recurs)
  # ... rest unchanged
end
```

**Why `kind: :reminder`?** The `Reminder` enum has three values: `reminder`, `timer`, `daily_reminder`. Adding a fourth requires a migration and an enum update. A relative reminder stored with `kind: "reminder"` is functionally identical at delivery time — `ReminderJob` generates `"It's X PM. Reminder: <message>"` for any non-timer kind. The only distinction is how `fire_at` was computed, which is irrelevant after creation. This keeps the schema stable.

**Turbo broadcast** (lines 113-116 of current code): the `else "reminders"` branch already handles any kind that is not `"timer"` or `"daily_reminder"`, so the new reminder broadcasts correctly to the `#reminders` list with no changes.

---

### 3. Tests

#### `spec/services/command_parser_spec.rb` — new contexts

```ruby
context "with 'set a reminder in 20 minutes to take the food out of the oven'" do
  it "returns :relative_reminder intent with minutes and message" do
    result = parser.parse("set a reminder in 20 minutes to take the food out of the oven")

    expect(result[:intent]).to eq(:relative_reminder)
    expect(result[:params][:minutes]).to eq(20)
    expect(result[:params][:message]).to eq("take the food out of the oven")
  end
end

context "with spoken number word ('set a reminder in twenty minutes to ...')" do
  it "normalises the word to an integer" do
    result = parser.parse("set a reminder in twenty minutes to check the oven")

    expect(result[:intent]).to eq(:relative_reminder)
    expect(result[:params][:minutes]).to eq(20)
  end
end

context "with singular 'minute'" do
  it "matches 'minute' as well as 'minutes'" do
    result = parser.parse("set a reminder in 1 minute to check the oven")

    expect(result[:intent]).to eq(:relative_reminder)
    expect(result[:params][:minutes]).to eq(1)
  end
end

context "without 'to' linking word (STT may omit it)" do
  it "still parses the message" do
    result = parser.parse("set a reminder in 5 minutes check the oven")

    expect(result[:intent]).to eq(:relative_reminder)
    expect(result[:params][:message]).to eq("check the oven")
  end
end
```

**Existing-but-untested forms** — add explicit test cases for the article-"a" variants in the existing `"set reminder at"` and `"set daily reminder at"` contexts:

```ruby
it "parses 'set a reminder at 9pm' (with article)" do
  result = parser.parse("set a reminder at 9pm to take medication")

  expect(result[:intent]).to eq(:reminder)
  expect(result[:params][:hour]).to eq(21)
  expect(result[:params][:message]).to eq("take medication")
end

it "parses 'set a daily reminder at 9pm' (with article)" do
  result = parser.parse("set a daily reminder at 9pm to take medication")

  expect(result[:intent]).to eq(:daily_reminder)
  expect(result[:params][:hour]).to eq(21)
  expect(result[:params][:message]).to eq("take medication")
end
```

#### `spec/services/command_responder_spec.rb` — new cases

```ruby
context "with :relative_reminder intent" do
  it "returns confirmation with the minute count" do
    command = { intent: :relative_reminder, params: { minutes: 20, message: "take the food out" } }

    expect(responder.respond(command: command, user: user)).to be_a(String)
    # response_text tested in isolation:
  end

  it "schedules a Reminder with kind: reminder and fire_at N minutes from now" do
    command = { intent: :relative_reminder, params: { minutes: 20, message: "take the food out" } }
    freeze_time do
      expect { described_class.new.respond(command: command, user: user) }
        .to change(Reminder, :count).by(1)
      reminder = Reminder.last
      expect(reminder.kind).to eq("reminder")
      expect(reminder.fire_at).to be_within(1.second).of(20.minutes.from_now)
      expect(reminder.message).to eq("take the food out")
      expect(reminder.recurs_daily).to be(false)
    end
  end
end
```

---

### 4. README (`README.md`)

Add three rows to the voice commands table:

| Say | Response |
|-----|----------|
| `"set a reminder in 20 minutes to take the food out of the oven"` | Confirms with "Reminder set for 20 minutes from now to ..."; speaks "It's X PM. Reminder: take the food out of the oven" when it fires |
| `"set a reminder at 9pm to take medication"` | Same as `"set 9pm reminder to..."` — "a reminder at" form also works |
| `"set a daily reminder at 9pm to take medication"` | Same as `"set daily 9pm reminder to..."` — "a daily reminder at" form also works |

---

### 5. Home page (`app/views/voice_commands/index.html.erb`)

Add the new command to the voice command list, alongside the existing reminder forms.

---

## Acceptance Criteria

- [x] `parser.parse("set a reminder in 20 minutes to take the food out of the oven")` returns `{ intent: :relative_reminder, params: { minutes: 20, message: "take the food out of the oven" } }`
- [x] Spoken number words normalise correctly ("twenty" → 20)
- [x] Singular "minute" matches as well as "minutes"
- [x] Omitting the "to" linking word still parses the message
- [x] `CommandResponder` confirms with "Reminder set for N minutes from now to <message>"
- [x] `Reminder` is created with `kind: "reminder"`, `fire_at: N.minutes.from_now`, `message:`, `recurs_daily: false`
- [x] Reminder appears in the `#reminders` section on the home page via Turbo broadcast
- [x] At `fire_at`, `ReminderJob` synthesizes `"It's X PM. Reminder: <message>"` (existing path, no changes needed)
- [x] `"set a reminder at 9pm"` and `"set a daily reminder at 9pm"` have explicit spec coverage confirming they already work
- [x] README updated with all three new command rows
- [x] Home page command list updated
- [x] A relative reminder created between two existing reminders appears between them in the `#reminders` list (verified via `Reminder#next_in_list` returning the correct sibling)
- [x] Full RSpec suite passes; RuboCop clean; mutant run against `CommandParser` and `CommandResponder`

---

## System-Wide Impact

- **No migration needed** — relative reminders store as `kind: "reminder"`. Existing enum values and schema unchanged.
- **`ReminderJob`** — unchanged. It reads `reminder.timer?` to branch delivery text; `kind: "reminder"` falls into the existing `"It's X PM. Reminder: ..."` path correctly.
- **`LoopingReminderDispatcher`** — unchanged. It falls through to `CommandParser` for any input that doesn't match a pending interaction or looping reminder command.
- **`VoiceCommandsController#index`** — unchanged. `@reminders = pending.reminder` already covers all `kind: "reminder"` rows, including relative reminders.
- **Turbo broadcast** — unchanged. The `else "reminders"` branch in `schedule_reminder` handles the new kind automatically.
- **`next_in_list` / display ordering** — `Reminder#next_in_list` for non-daily reminders uses `siblings.order(:fire_at).where("fire_at > ?", fire_at).first` (line 47 of `app/models/reminder.rb`). A relative reminder created at 5:27 PM with a 20-minute interval (`fire_at = 5:47 PM`) will correctly find a 6:00 PM sibling as its `next_in_list` and broadcast `before` it — placing it between the 5:30 PM and 6:00 PM reminders with no code changes needed. Add a test case to verify this.

---

## Dependencies & Risks

- **STT omits "to"**: Deepgram may transcribe "set a reminder in 20 minutes check the oven" without the linking word. The `(?:to\s+)?` makes it optional. Add a test without "to".
- **STT omits "set a"**: Transcript may begin with "reminder in 20 minutes to...". The `\breminder` anchor handles this — "set a" is not required.
- **Large N**: "set a reminder in 120 minutes" works fine — `\d+` is unbounded. No validation needed in the parser; the app already trusts parsed params.
- **Shadowing risk**: `relative_reminder_command` must run *before* `scheduled_reminder_command`. The scheduled reminder regexes require `am|pm` so there is no overlap, but insertion order is still important.
- **`:00` in delivery text**: `ReminderJob` uses the existing `format_time` helper which already omits `:00` when minutes are zero (ElevenLabs TTS `:00` → "hundred" bug, documented in `docs/solutions/`). No new time formatting is introduced.

---

## Sources & References

- `app/services/command_parser.rb` — existing `relative_reminder_command` insertion point at line 23
- `app/services/command_responder.rb` — `schedule_reminder` line 84, `response_text` line 20
- `spec/services/command_parser_spec.rb` — add contexts after existing `"run looping reminder"` contexts
- `spec/services/command_responder_spec.rb` — add `:relative_reminder` context
- `docs/solutions/integration-issues/deepgram-quote-stripping-regex-and-x-status-text-pattern.md` — regex conventions for STT input
- `docs/solutions/integration-issues/elevenlabs-tts-colon-zero-zero-sounds-like-hundred.md` — time formatting in TTS responses
