---
status: complete
priority: p2
issue_id: "030"
tags: [code-review, performance, rails, quality]
---

# Remove Redundant `includes(:user)` from VoiceCommandsController

## Problem Statement

`VoiceCommandsController#index` loads reminders with `includes(:user)` on a relation already scoped to `current_user`. Every `Reminder` returned belongs to `current_user`, which is already loaded and held in memory. The `includes(:user)` directive triggers a second SQL query (`SELECT * FROM users WHERE id = $1`) that returns a single row — the user you already have. This is a wasted database round-trip that also trains future readers to expect user association access on reminders, which can cargo-cult `includes(:user)` into scopes where it causes real N+1 problems.

## Findings

- `app/controllers/voice_commands_controller.rb` line 3:
  ```ruby
  pending = current_user.reminders.pending.where("fire_at > ?", Time.current).includes(:user).order(:fire_at)
  ```
- `current_user.reminders` is already user-scoped — no cross-user data possible
- `current_user` is already in memory (set by `AuthenticatedController`)
- The `sort_by` block in the daily reminders branch uses `current_user.timezone` directly — it does NOT access `r.user` — so no N+1 risk exists even without `includes(:user)`
- Performance oracle: "One extra query returning one row is invisible in profiling. However, this pattern trains readers of the code to expect user association access on each reminder."

## Proposed Solutions

### Option A: Remove `includes(:user)` entirely (Recommended)

```ruby
pending = current_user.reminders.pending.where("fire_at > ?", Time.current).order(:fire_at)
```

Ensure the view partial and any helper that access `reminder.user` are updated to use a locally available variable or `current_user` if they're always the same user.

Effort: Small | Risk: Low (verify view/partial does not call `reminder.user` in a loop)

### Option B: Keep but add comment explaining intent

If `reminder.user` IS accessed in the partial (e.g. for `time_of_day_minutes`), keep `includes(:user)` with a comment:
```ruby
# includes(:user) because _reminder.html.erb accesses reminder.user.timezone
```

Effort: Trivial | Risk: None

## Acceptance Criteria

- [ ] No redundant `SELECT * FROM users` query on the voice_commands index action
- [ ] All existing controller tests pass
- [ ] If `reminder.user` is accessed in the view/partial, confirm it is N+1-safe

## Work Log

- 2026-02-24: Identified by performance-oracle during code review (finding #3)
- 2026-02-24: Investigated. `includes(:user)` is load-bearing — `app/views/reminders/_reminder.html.erb`
  accesses `reminder.user.timezone` on lines 6 and 12 for both the timer and non-timer display branches.
  Without `includes(:user)` the index action would trigger N+1 queries (one `SELECT users` per reminder).
  The partial is also rendered via Turbo Stream broadcasts where `current_user` is not available, so the
  association must be accessible on the reminder object itself. The "one extra query returning one row"
  is actually preventing N queries, not wasting one. No change needed — wontfix.
