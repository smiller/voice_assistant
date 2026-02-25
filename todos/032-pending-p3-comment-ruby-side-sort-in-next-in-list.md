---
status: pending
priority: p3
issue_id: "032"
tags: [code-review, documentation, rails, quality]
---

# Add Comment Explaining Ruby-Side Sort in next_in_list Daily Branch

## Problem Statement

`Reminder#next_in_list` uses different strategies for the two reminder kinds: SQL `ORDER BY + WHERE` for non-daily reminders, Ruby-side `sort_by + find` for daily reminders. The asymmetry is correct (daily reminders must sort by time-of-day in the user's timezone, which cannot be expressed simply in DB-agnostic SQL), but it is not explained. A future reviewer will reach for the obvious database fix and wonder why it was not done.

## Findings

- `app/models/reminder.rb` lines 38-41: daily reminder branch loads all siblings into Ruby
- Rails reviewer finding #2: "This needs to be documented. The comment 'sort by time-of-day because daily reminders can be scheduled on different calendar dates' would make the intent immediately legible."
- Performance oracle: confirmed the in-memory approach is appropriate for < 20 daily reminders per user

## Proposed Fix

```ruby
def next_in_list
  siblings = user.reminders.pending.where("fire_at > ?", Time.current).where.not(id: id).public_send(kind)

  if daily_reminder?
    # Daily reminders repeat; their fire_at date is the next upcoming occurrence, not
    # a display attribute. Two siblings can have different fire_at dates (e.g. "7 AM
    # tomorrow" vs "11 PM tonight") but must sort by clock time regardless of calendar
    # date. We cannot express this time-of-day ordering in DB-agnostic SQL without a
    # computed column, so we sort in Ruby. Acceptable for < ~20 daily reminders per user.
    my_minutes = time_of_day_minutes(fire_at)
    siblings.sort_by { |r| time_of_day_minutes(r.fire_at) }
            .find { |r| time_of_day_minutes(r.fire_at) > my_minutes }
  else
    siblings.order(:fire_at).where("fire_at > ?", fire_at).first
  end
end
```

## Acceptance Criteria

- [ ] Comment explains the asymmetry between daily and non-daily branches
- [ ] Comment explains why DB-side sort is not used for daily reminders
- [ ] No behaviour change

## Work Log

- 2026-02-24: Identified by kieran-rails-reviewer during code review (finding #2)
