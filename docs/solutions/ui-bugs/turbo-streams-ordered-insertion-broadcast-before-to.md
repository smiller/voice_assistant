---
title: "Turbo Streams ordered insertion using broadcast_before_to"
date: 2026-02-24
problem_type: ui-bug
component: turbo_streams
tags:
  - turbo-streams
  - hotwire
  - rails
  - real-time-ui
  - broadcast
  - ordered-lists
  - reminders
symptoms:
  - New reminders always appended to end of list regardless of sort order
  - List requires page refresh to show correct order
  - broadcast_append_to ignores sort position
  - Voice-commanded reminders inserted out of chronological sequence
affected_files:
  - app/models/reminder.rb
  - app/services/command_responder.rb
  - app/jobs/reminder_job.rb
related_specs:
  - spec/models/reminder_spec.rb
  - spec/services/command_responder_spec.rb
  - spec/jobs/reminder_job_spec.rb
---

# Turbo Streams Ordered Insertion using broadcast_before_to

## Problem Symptom

Adding a new reminder via voice command always placed it at the end of the list in the UI, regardless of its scheduled time. Adding "5 PM — do something" when "6 PM — do something else" was already visible would produce the wrong order until the page was refreshed. Daily reminders had the same issue: a new "7 AM" daily reminder appended after an existing "11 PM" one.

## Root Cause

The app always called `broadcast_append_to` when inserting a new reminder into the live list, which placed the new element at the end of the DOM container regardless of the reminder's sorted position (by `fire_at` for timers/one-off reminders, or by time-of-day for daily reminders). The list appeared correctly ordered on a full page load because the view query sorted records, but real-time insertions via Turbo Streams bypassed that ordering entirely.

The footgun is subtle: `broadcast_append_to` feels correct during development because items are usually inserted in chronological order during manual testing. It breaks in production (or when the voice assistant creates a reminder earlier in time than one already set) when items arrive out of logical order.

## Working Solution

### Step 1: Add `Reminder#next_in_list`

Add a method to `app/models/reminder.rb` that finds the first pending sibling of the same `kind` and same user that should appear after `self` in the sorted list. For daily reminders, sorting is by time-of-day in the user's timezone (ignoring the calendar date, since daily reminders repeat). For all other kinds, sorting is by absolute `fire_at` timestamp.

```ruby
# app/models/reminder.rb
def next_in_list
  siblings = user.reminders.pending.where("fire_at > ?", Time.current).where.not(id: id).public_send(kind)

  if daily_reminder?
    my_minutes = time_of_day_minutes(fire_at)
    siblings.sort_by { |r| time_of_day_minutes(r.fire_at) }
            .find { |r| time_of_day_minutes(r.fire_at) > my_minutes }
  else
    siblings.order(:fire_at).where("fire_at > ?", fire_at).first
  end
end

private

def time_of_day_minutes(timestamp)
  local = timestamp.in_time_zone(user.timezone)
  local.hour * 60 + local.min
end
```

The key design choices:
- **Kind scoping** via `public_send(kind)` — timers, reminders, and daily reminders are displayed in separate lists, so siblings must be of the same kind.
- **Daily reminders sort by time-of-day**, not `fire_at`. A "7 AM" daily reminder that fires tomorrow still sorts before an "11 PM" one that fires tonight because the lists display a recurring schedule, not a timeline.
- **Regular reminders use absolute `fire_at`** — the correct simple case.

### Step 2: Update `CommandResponder` to use `broadcast_before_to`

In `app/services/command_responder.rb`, replace the unconditional `broadcast_append_to` in `schedule_reminder` with a conditional. Use `broadcast_before_to` when a later sibling exists, fall back to `broadcast_append_to` when the new reminder belongs at the end. Note that `CommandResponder` does not include `ActionView::RecordIdentifier`, so reference the module explicitly.

**Before (always appended):**
```ruby
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
```

**After (inserts at correct sorted position):**
```ruby
next_reminder = reminder.next_in_list
if next_reminder
  Turbo::StreamsChannel.broadcast_before_to(
    reminder.user,
    target: ActionView::RecordIdentifier.dom_id(next_reminder),
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
```

### Step 3: Update `ReminderJob` daily reschedule to use `broadcast_before_to`

Apply the same conditional pattern in `app/jobs/reminder_job.rb` when rescheduling a fired daily reminder for the next day. `ReminderJob` already includes `ActionView::RecordIdentifier`, so `dom_id` is available directly.

**Before:**
```ruby
Turbo::StreamsChannel.broadcast_append_to(
  new_reminder.user,
  target: "daily_reminders",
  partial: "reminders/reminder",
  locals: { reminder: new_reminder }
)
```

**After:**
```ruby
next_sibling = new_reminder.next_in_list
if next_sibling
  Turbo::StreamsChannel.broadcast_before_to(
    new_reminder.user,
    target: dom_id(next_sibling),
    partial: "reminders/reminder",
    locals: { reminder: new_reminder }
  )
else
  Turbo::StreamsChannel.broadcast_append_to(
    new_reminder.user,
    target: "daily_reminders",
    partial: "reminders/reminder",
    locals: { reminder: new_reminder }
  )
end
```

## Key Insight

`broadcast_append_to` and `broadcast_prepend_to` insert relative to a **container element**. `broadcast_before_to` (and `broadcast_after_to`) insert relative to a **specific sibling element** identified by DOM id.

**Rule of thumb:** If the controller query that renders the initial list has an `order` clause, every real-time broadcast for that list must respect that same order. `broadcast_append_to` cannot do this. `broadcast_before_to` can — by targeting the `dom_id` of the record that should appear immediately after the new one.

When `next_in_list` returns `nil` (the new item belongs at the end), `broadcast_append_to` is still the correct fallback.

This pattern requires no changes to view templates or initial page-load queries — only the broadcast call site changes.

---

## Prevention & Best Practices

### When to use `broadcast_before_to` vs `broadcast_append_to`

**Use `broadcast_append_to` when:**
- Order does not matter (activity feeds, logs where newest-at-bottom is correct by definition)
- The list is sorted by insertion time and new items genuinely belong at the end
- The list is re-rendered server-side after each change (Turbo Frame replace)

**Use `broadcast_before_to` when:**
- The list is sorted by any attribute other than raw insertion order (time, priority, alphabetical)
- Users expect the list to stay sorted without a page refresh
- The controller/scope loading the list contains an `order` clause

### General pattern for sorted real-time lists

**1. Define a canonical ordering scope with a tiebreaker:**

```ruby
scope :by_fire_at, -> { order(fire_at: :asc, id: :asc) }
```

Always include a tiebreaker (`:id` works). Without one, two records with identical sort key values produce non-deterministic `next_in_list` results.

**2. Implement `next_in_list`** scoped to the record's owner:

```ruby
def next_in_list
  user.reminders.by_fire_at
      .where("fire_at > ? OR (fire_at = ? AND id > ?)", fire_at, fire_at, id)
      .first
end
```

**3. Use the conditional broadcast pattern:**

```ruby
if (sibling = record.next_in_list)
  Turbo::StreamsChannel.broadcast_before_to(
    stream, target: ActionView::RecordIdentifier.dom_id(sibling), ...
  )
else
  Turbo::StreamsChannel.broadcast_append_to(stream, target: container_id, ...)
end
```

### Testing strategy

**Unit test: assert `next_in_list` returns the correct sibling**

```ruby
describe "#next_in_list" do
  let(:user) { create(:user, timezone: "America/New_York") }

  it "returns nil when no other reminders are pending" do
    reminder = create(:reminder, user: user, fire_at: 2.hours.from_now)
    expect(reminder.next_in_list).to be_nil
  end

  it "returns the first reminder that fires after it" do
    earlier = create(:reminder, user: user, fire_at: 1.hour.from_now)
    later   = create(:reminder, user: user, fire_at: 3.hours.from_now)
    expect(earlier.next_in_list).to eq(later)
  end

  it "does not return reminders of a different kind" do
    reminder = create(:reminder, user: user, fire_at: 1.hour.from_now)
    _timer   = create(:reminder, :timer, user: user, fire_at: 2.hours.from_now)
    expect(reminder.next_in_list).to be_nil
  end

  it "does not return cancelled or delivered reminders" do
    reminder   = create(:reminder, user: user, fire_at: 1.hour.from_now)
    _cancelled = create(:reminder, user: user, fire_at: 2.hours.from_now, status: "cancelled")
    expect(reminder.next_in_list).to be_nil
  end

  context "for daily reminders (sort by time-of-day, not absolute fire_at)" do
    it "uses time-of-day not absolute fire_at — 11pm tonight sorts before 7am tomorrow" do
      travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
        eleven_pm = create(:reminder, :daily, user: user,
                           fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })
        seven_am  = create(:reminder, :daily, user: user,
                           fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 7, 0, 0) })

        expect(seven_am.next_in_list).to eq(eleven_pm)
      end
    end
  end
end
```

**Service/request test: assert `broadcast_before_to` is called when a sibling exists**

```ruby
context "when a later reminder already exists" do
  before { allow(Turbo::StreamsChannel).to receive(:broadcast_before_to) }

  it "broadcasts before the existing later reminder instead of appending" do
    later = create(:reminder, user: user, message: "later event",
                   fire_at: 2.hours.from_now)

    responder.respond(
      command: { intent: :reminder, params: { hour: 21, minute: 0, message: "earlier event" } },
      user: user
    )

    new_reminder = Reminder.find_by(message: "earlier event")
    expect(Turbo::StreamsChannel).to have_received(:broadcast_before_to)
      .with(user, target: ActionView::RecordIdentifier.dom_id(later),
            partial: "reminders/reminder", locals: { reminder: new_reminder })
  end
end
```

**Watch out:** The factory default message may collide with the command message, causing `find_by(message: ...)` to return the wrong record. Give fixture records an explicit message that differs from the command's message.

### Pitfalls to avoid

| Pitfall | Problem | Fix |
|---------|---------|-----|
| `broadcast_append_to` for sorted lists | Items arrive out of order under real usage | Use `broadcast_before_to` + `next_in_list` |
| Missing tiebreaker in ordering scope | Non-deterministic results when sort keys are equal | Always include `id: :asc` as a secondary sort |
| `next_in_list` not scoped to record owner | Returns siblings from other users; `broadcast_before_to` targets a DOM id that doesn't exist in the subscriber's page, silently dropped | Scope query to `user.reminders` |
| Partial missing `id="<%= dom_id(record) %>"` | `broadcast_before_to` lookup fails silently | Ensure every partial's outermost element has the correct `dom_id` |
| Sort key updated without re-broadcasting position | `broadcast_replace_to` updates content in place but leaves element at wrong position | Treat sort key updates as remove + reinsert at new position |
| Factory default message matching command message | `find_by(message: ...)` in tests returns the wrong record | Give fixture records an explicit, distinct message |

---

## Sources & References

### Related project documents

- **`docs/plans/2026-02-24-feat-display-pending-timers-reminders-plan.md`** — Original plan documenting `broadcast_append_to` / `broadcast_remove_to` patterns and the three-list UI structure (`#timers`, `#reminders`, `#daily_reminders`)
- **`docs/plans/2026-02-23-feat-voice-assistant-rails-app-plan.md`** (Phase 4) — Architecture showing `ReminderJob#perform` → `Turbo::StreamsChannel.broadcast_append_to`
- **`docs/brainstorms/2026-02-24-pending-timers-reminders-display-brainstorm.md`** — Decision rationale for inline rendering + live Turbo Stream updates

### Existing solution docs

- `docs/solutions/logic-errors/command-parser-spoken-time-parsing-bugs.md` — unrelated (Deepgram parsing)
- `docs/solutions/integration-issues/empty-webm-audio-deepgram-400-corrupt-data.md` — unrelated (audio upload)
