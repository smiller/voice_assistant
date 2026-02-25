---
title: "Daily Reminders: Sort by Time-of-Day, Not Absolute fire_at"
date: 2026-02-24
problem_type: logic-error
component: voice_commands_controller
tags:
  - sorting
  - daily-reminders
  - timezone
  - fire_at
  - time-of-day
  - hotwire
symptoms:
  - "'7 AM' daily reminder appears after '11 PM' in the list"
  - "Daily reminders displayed in chronological fire_at order rather than clock order"
  - "List appears correct after page refresh only when all reminders were created in clock order"
  - "Reminders spanning midnight render in the wrong visual sequence"
affected_files:
  - app/controllers/voice_commands_controller.rb
  - spec/controllers/voice_commands_controller_spec.rb
related_specs:
  - spec/controllers/voice_commands_controller_spec.rb
---

# Daily Reminders: Sort by Time-of-Day, Not Absolute fire_at

## Problem Symptom

The daily reminders section of the voice assistant home page showed "11 PM" before "7 AM" when the 11 PM reminder was scheduled for that same night and the 7 AM reminder was scheduled for the following morning. Visually, the list appeared in raw chronological order rather than in clock order — which is what a user of a daily reminder app expects.

Example: At 10 PM on Feb 24, if you had set an "11 PM – write journal" reminder earlier tonight and a "7 AM – morning pages" reminder, the list showed:

```
11 PM — write journal
7 AM — morning pages
```

When the user expected:

```
7 AM — morning pages
11 PM — write journal
```

## Root Cause

The controller loaded daily reminders with a plain `order(:fire_at)` via the shared `pending` scope:

```ruby
pending = current_user.reminders.pending.where("fire_at > ?", Time.current).includes(:user).order(:fire_at)
@daily_reminders = pending.daily_reminder
```

`order(:fire_at)` sorts by the absolute UTC timestamp. A "7 AM tomorrow" reminder has a `fire_at` that is later than an "11 PM tonight" reminder. So the 11 PM record comes first in absolute time, even though it is later in clock time.

Daily reminders are a recurring schedule, not a one-off timeline. Users think of them as "things that happen at 7 AM every day" — the date component of `fire_at` is an implementation detail, not part of the display order.

## Working Solution

Break daily reminders out of the ActiveRecord chain and sort them in Ruby by local hour/minute in the user's timezone:

**Before:**

```ruby
pending = current_user.reminders.pending.where("fire_at > ?", Time.current).includes(:user).order(:fire_at)
@timers          = pending.timer
@reminders       = pending.reminder
@daily_reminders = pending.daily_reminder
```

**After (`app/controllers/voice_commands_controller.rb`):**

```ruby
pending = current_user.reminders.pending.where("fire_at > ?", Time.current).includes(:user).order(:fire_at)
@timers          = pending.timer
@reminders       = pending.reminder
@daily_reminders = pending.daily_reminder.sort_by { |r|
  local = r.fire_at.in_time_zone(current_user.timezone)
  [ local.hour, local.min ]
}
```

The `[hour, min]` tuple sorts lexicographically by time-of-day. The result is a plain Ruby Array, which works correctly with `@daily_reminders.each` in the view.

### Test (`spec/controllers/voice_commands_controller_spec.rb`)

Replace the trivially-ordered `fire_at` test with a cross-midnight test:

```ruby
it "renders pending daily_reminders ordered by time of day in the user's timezone, not absolute fire_at" do
  # 10 PM ET: 11 PM fires tonight (earlier fire_at), 7 AM fires tomorrow (later fire_at)
  travel_to Time.new(2026, 2, 24, 3, 0, 0, "UTC") do  # 10:00 PM ET
    eleven_pm = create(:reminder, :daily, user: user,
                       fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 23, 0, 0) })
    seven_am  = create(:reminder, :daily, user: user,
                       fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 25, 7, 0, 0) })

    get "/voice_commands"

    expect(response.body.index("reminder_#{seven_am.id}"))
      .to be < response.body.index("reminder_#{eleven_pm.id}")
  end
end
```

The test fails on `order(:fire_at)` (11 PM fires first) and passes with `sort_by { [local.hour, local.min] }`.

## Key Insight

**`fire_at` is a calendar timestamp. Time-of-day is a display concept.**

Daily reminders repeat. Their `fire_at` is always "the next upcoming occurrence", which means a "7 AM" reminder scheduled for tomorrow necessarily has a later `fire_at` than an "11 PM tonight" reminder. Sorting by `fire_at` produces chronological order across the timeline — which is correct for one-off reminders but wrong for a recurring schedule that users read as a clock.

The fix is deliberate: accept that the DB sort is wrong for this subtype and override it in Ruby. The trade-off (loading all daily reminders into memory for sort) is acceptable because users typically have fewer than 20 daily reminders.

---

## Prevention & Best Practices

### When `order(:fire_at)` is wrong

`order(:fire_at)` is correct for:
- One-off timers and reminders (sort by when they fire)
- Activity feeds (sort by when they were created)

`order(:fire_at)` is wrong for:
- Recurring items where the user expects clock order (daily reminders, weekly schedules)
- Any list where the *date* component of the timestamp is an implementation artifact, not a sorting signal

### Write cross-midnight tests for sort behavior

A same-day sort test (both reminders fire on the same calendar date) will pass regardless of whether you use `order(:fire_at)` or time-of-day sort — they agree. Only a cross-midnight test (one reminder fires today, another tomorrow) distinguishes them.

Always set up the test with:
1. An "earlier in the day" reminder that fires *tomorrow* (later `fire_at`)
2. A "later in the day" reminder that fires *tonight* (earlier `fire_at`)

If the test passes, the sort is correct. If it fails, `fire_at` is driving the order.

### Use `travel_to` with explicit timezone-aware timestamps

```ruby
travel_to Time.new(2026, 2, 24, 3, 0, 0, "UTC") do  # 10:00 PM ET
  fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 23, 0, 0) }
end
```

Using `Time.use_zone` + `Time.zone.local` guarantees the `fire_at` is the right wall-clock time in the user's timezone, regardless of where the test runner is located.

### Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| `order(:fire_at)` for daily reminders | Cross-midnight: later `fire_at` ≠ later time-of-day | `sort_by { [local.hour, local.min] }` in Ruby |
| Same-day sort test | Passes for both `fire_at` and time-of-day sort | Always test cross-midnight scenario |
| Forgetting to scope by timezone | `Time.current.hour` is UTC, not user's local hour | `fire_at.in_time_zone(user.timezone)` before extracting `hour`/`min` |

---

## Sources & References

### Related project documents

- **`docs/solutions/ui-bugs/turbo-streams-ordered-insertion-broadcast-before-to.md`** — The same time-of-day vs `fire_at` distinction drove the `next_in_list` logic for `broadcast_before_to`. Both fixes share the same root insight.
- **`docs/brainstorms/2026-02-24-pending-timers-reminders-display-brainstorm.md`** — Original decision to display daily reminders in a separate list
- **`docs/plans/2026-02-24-feat-display-pending-timers-reminders-plan.md`** — Plan that introduced the initial `order(:fire_at)` for all three lists
