---
title: "Reminder: Day-Label Logic Moved from ERB Partial to Reminder#day_label"
date: 2026-02-24
problem_type: logic-error
component: reminder_model
tags:
  - erb-logic-in-view
  - model-method-extraction
  - timezone
  - day-label
  - daily-reminder
  - refactor
symptoms:
  - "Daily reminders incorrectly displayed 'today' or 'tomorrow' labels in the reminder list"
  - "Day-label logic was duplicated in the ERB partial and could not be unit tested"
  - "Timezone edge cases (UTC date ahead of user's local date) were silently wrong in the view"
affected_files:
  - app/models/reminder.rb
  - app/views/reminders/_reminder.html.erb
  - spec/models/reminder_spec.rb
related_specs:
  - spec/models/reminder_spec.rb
---

# Reminder: Day-Label Logic Moved from ERB Partial to Reminder#day_label

## Problem Symptom

The reminder list partial rendered a day label ("today", "tomorrow", or "Mar 1") beside every reminder — including daily reminders, which repeat every day and should show no day label at all. Because the logic lived inline in the ERB partial, the bug was invisible to RSpec and could not be caught by any model or unit test.

## Root Cause

The `_reminder.html.erb` partial computed the day label with a `case` expression directly in the view:

```erb
<% today = Time.current.in_time_zone(reminder.user.timezone).to_date %>
<% day_label = case local_fire_at.to_date
               when today       then "today"
               when today + 1   then "tomorrow"
               else               local_fire_at.strftime("%b %-d")
               end %>
```

Two problems:

1. **No guard for daily reminders.** The `case` expression ran for every reminder regardless of `kind`. A `daily_reminder` always landed on either "today" or "tomorrow" because its `fire_at` is always near the current time, producing a misleading label.

2. **Untestable location.** Business logic embedded in a view cannot be exercised by model specs. Timezone edge cases (e.g., 2 AM UTC = 9 PM the previous day in ET) were silently unverified.

## Working Solution

### `app/models/reminder.rb` — new method

```ruby
def day_label
  return nil if daily_reminder?

  local_date = fire_at.in_time_zone(user.timezone).to_date
  today      = Time.current.in_time_zone(user.timezone).to_date

  case local_date
  when today     then "today"
  when today + 1 then "tomorrow"
  else                local_date.strftime("%b %-d")
  end
end
```

### `app/views/reminders/_reminder.html.erb` — after

```erb
<span>
  <%= local_fire_at.strftime("%-I:%M %p") %><%= " #{reminder.day_label}" if reminder.day_label %> — <%= reminder.message %>
</span>
```

The partial now delegates entirely to the model. When `day_label` returns `nil` (daily reminders), nothing is interpolated.

### `spec/models/reminder_spec.rb` — key examples added

```ruby
describe "#day_label" do
  let(:user) { build(:user, timezone: "America/New_York") }

  context "when kind is daily_reminder" do
    it "returns nil" do
      reminder = build(:reminder, kind: :daily_reminder, user: user,
                       fire_at: Time.new(2026, 2, 24, 12, 0, 0, "UTC"), recurs_daily: true)
      expect(reminder.day_label).to be_nil
    end
  end

  context "when fire_at is today in the user's timezone" do
    it "returns 'today'" do
      travel_to Time.new(2026, 2, 24, 14, 0, 0, "UTC") do  # 9:00 AM ET
        reminder = build(:reminder, user: user,
                         fire_at: Time.new(2026, 2, 24, 23, 0, 0, "UTC"))  # 6:00 PM ET
        expect(reminder.day_label).to eq("today")
      end
    end
  end

  context "when fire_at is tomorrow in the user's timezone" do
    it "returns 'tomorrow'" do
      travel_to Time.new(2026, 2, 24, 14, 0, 0, "UTC") do
        reminder = build(:reminder, user: user,
                         fire_at: Time.new(2026, 2, 25, 12, 0, 0, "UTC"))
        expect(reminder.day_label).to eq("tomorrow")
      end
    end
  end

  context "when fire_at is a later date" do
    it "returns a formatted date string" do
      travel_to Time.new(2026, 2, 24, 14, 0, 0, "UTC") do
        reminder = build(:reminder, user: user,
                         fire_at: Time.new(2026, 3, 1, 12, 0, 0, "UTC"))
        expect(reminder.day_label).to eq("Mar 1")
      end
    end
  end

  context "when UTC date is ahead of the user's local date" do
    it "uses the user's timezone for 'today', not the UTC date" do
      travel_to Time.new(2026, 2, 25, 2, 0, 0, "UTC") do  # 9 PM ET on Feb 24
        reminder = build(:reminder, user: user,
                         fire_at: Time.new(2026, 2, 25, 2, 0, 0, "UTC"))
        expect(reminder.day_label).to eq("today")
      end
    end

    it "uses the user's timezone for 'tomorrow', not the UTC date" do
      travel_to Time.new(2026, 2, 25, 2, 0, 0, "UTC") do
        reminder = build(:reminder, user: user,
                         fire_at: Time.new(2026, 2, 25, 12, 0, 0, "UTC"))
        expect(reminder.day_label).to eq("tomorrow")
      end
    end
  end
end
```

## Key Insight

**Both sides of the date comparison must use the same timezone.** The bug class here is not merely "logic in a view" — it is "logic that depends on timezone-relative state and cannot be proven correct without time-travel tests." Moving the method to the model is a prerequisite for writing those tests at all.

The `nil` sentinel from `day_label` for daily reminders is the right return value for view integration: `" #{reminder.day_label}" if reminder.day_label` cleanly suppresses the label with no special-case branching in the partial.

---

## Prevention & Best Practices

### Move display-logic predicates to the model

Move any `case`/`if` expression in a view to a model method as soon as it:
- Branches on record state (e.g., `kind`, `status`)
- Depends on `Time.current` or a user-scoped timezone
- Could produce different output for different record subtypes

A method in the model can be tested with `travel_to` and `build`. A `case` in a view cannot.

### Return `nil` from label helpers that should suppress output

Returning `nil` (not `""`) from display helpers lets the view use simple `if` guards:

```erb
<%= " #{reminder.day_label}" if reminder.day_label %>
```

An empty string would still render a leading space. `nil` suppresses both the space and the label with a single condition.

### Guard by `kind` first

Early-return guards (`return nil if daily_reminder?`) make the method's preconditions explicit and are the first thing covered by tests. If a method only applies to a subset of record types, say so immediately.

### Use `travel_to` with explicit UTC timestamps in timezone tests

```ruby
travel_to Time.new(2026, 2, 25, 2, 0, 0, "UTC") do  # 9 PM ET on Feb 24
  # fire_at in UTC = Feb 25, but in ET it is still Feb 24 → should return "today"
end
```

Without pinning `Time.current`, timezone tests are brittle and fail at midnight or when run from a different timezone. Pin both the "now" moment and the `fire_at` to specific UTC timestamps.

### Pitfalls

| Pitfall | Problem | Fix |
|---------|---------|-----|
| Business logic in ERB | Cannot unit-test; timezone bugs are silent | Extract to model method |
| Forgetting to guard by `kind` | Daily reminders get a spurious "today"/"tomorrow" label | `return nil if daily_reminder?` first |
| Comparing `.to_date` without timezone | `Time.current.to_date` is UTC, not user's local date | Always `in_time_zone(user.timezone).to_date` on both sides |
| Not testing the UTC-ahead-of-local edge case | 2 AM UTC = 9 PM yesterday in ET — tests pass in CI but fail for users near midnight | Add explicit `travel_to` test for this scenario |

---

## Sources & References

### Related project documents

- **`docs/solutions/logic-errors/daily-reminders-sort-by-time-of-day-not-fire-at.md`** — The same timezone-vs-UTC confusion drove the controller sort bug. Both share the root cause: confusing UTC timestamps with user-local dates.
- **`docs/plans/2026-02-24-feat-display-pending-timers-reminders-plan.md`** — Original plan that introduced the `_reminder.html.erb` partial with inline day-label logic
