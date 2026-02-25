---
status: complete
priority: p3
issue_id: "033"
tags: [code-review, documentation, rails, quality]
---

# Add Comment on `public_send(kind)` Enum Key-Value Coupling in next_in_list

## Problem Statement

`Reminder#next_in_list` calls `.public_send(kind)` to dispatch to the correct AR scope (`.timer`, `.reminder`, `.daily_reminder`). This relies on the enum's string values matching the scope method names exactly. The enum was defined with key names that match their string values (`reminder: "reminder"` etc.), so `public_send("daily_reminder")` works. But this coupling is invisible — if someone renames a string value without renaming the key (`daily_reminder: "recurring"`), `public_send("recurring")` will raise `NoMethodError` at runtime rather than a clear message at load time.

## Findings

- `app/models/reminder.rb` line 35: `.public_send(kind)` — `kind` returns the stored string value
- Rails enum generates scopes named after the **key** (`:daily_reminder`), not the stored string
- Current enum definition: `enum :kind, { reminder: "reminder", daily_reminder: "daily_reminder", timer: "timer" }` — keys == values, so the trick works
- Rails reviewer finding #5: "If anyone renames the string value without renaming the key, `public_send(kind)` will silently call a non-existent method and raise NoMethodError."

## Proposed Fix

```ruby
siblings = user.reminders.pending
                          .where("fire_at > ?", Time.current)
                          .where.not(id: id)
                          .public_send(kind)  # kind returns the string value; works because
                                              # enum string values match scope method names
                                              # (e.g. kind == "daily_reminder" → .daily_reminder scope)
                                              # If you rename a string value, update the scope name too.
```

Alternatively, use `kind_before_type_cast` which returns the symbol key:
```ruby
.public_send(kind_before_type_cast)  # returns :daily_reminder, not "daily_reminder"
```

Both produce the same result today; the second is more robust to string-value renames.

## Acceptance Criteria

- [ ] The `public_send(kind)` line has an explanatory comment OR is replaced with `public_send(kind_before_type_cast)` for robustness
- [ ] No behaviour change

## Work Log

- 2026-02-24: Identified by kieran-rails-reviewer during code review (finding #5)
