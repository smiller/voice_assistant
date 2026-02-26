---
status: complete
priority: p2
issue_id: "065"
tags: [code-review, performance, looping-reminders, database, quality]
dependencies: []
---

# `broadcast_loop_replace` Always Re-Queries the DB to Reload Associations

## Problem Statement

`broadcast_loop_replace` unconditionally reloads the looping reminder and its aliases from the database, even when the caller already has the record in memory and no association has changed:

```ruby
def broadcast_loop_replace(user, reminder)
  reminder_with_aliases = user.looping_reminders.includes(:command_aliases).find(reminder.id)
  ...
end
```

It is called from three sites:
- `handle_stop_loop` — `reminder.stop!` already called; no aliases changed. Re-query wasteful.
- `handle_run_loop` — `reminder.activate!` already called; no aliases changed. Re-query wasteful.
- `create_command_alias` — a new alias was just created; associations need refreshing. Re-query correct.

## Findings

- `app/services/command_responder.rb:220-228` — unconditional `includes(:command_aliases).find(reminder.id)`
- Called at lines 162, 152, 216 — only the third call site (`create_command_alias`) actually needs a reload.
- Identified by code-simplicity-reviewer (P2).

## Proposed Solutions

### Option A: Accept a pre-loaded object; reload only in `create_command_alias` (Recommended)

```ruby
def broadcast_loop_replace(user, reminder)
  Turbo::StreamsChannel.broadcast_replace_to(
    user,
    target: dom_id(reminder),
    partial: "looping_reminders/looping_reminder",
    locals: { looping_reminder: reminder }
  )
end
```

In `create_command_alias`, pass the reminder after reloading aliases:
```ruby
looping_reminder.command_aliases.reload
broadcast_loop_replace(user, looping_reminder)
```

**Pros:** Two fewer DB queries per stop/activate call; simpler method signature.
**Cons:** Callers must ensure reminder is loaded with associations when needed.

**Effort:** 1 hour
**Risk:** Low

---

### Option B: Add `needs_reload:` keyword argument

```ruby
def broadcast_loop_replace(user, reminder, needs_reload: false)
  r = needs_reload ? user.looping_reminders.includes(:command_aliases).find(reminder.id) : reminder
  ...
end
```

**Pros:** Explicit at call site.
**Cons:** More method parameters; still doing the full DB re-query.

**Effort:** 45 minutes
**Risk:** Low

## Recommended Action

Option A.

## Technical Details

**Affected files:**
- `app/services/command_responder.rb:162, 152, 216, 220-228`

## Acceptance Criteria

- [ ] `handle_stop_loop` and `handle_run_loop` do not trigger an extra DB query
- [ ] `create_command_alias` still correctly renders updated aliases
- [ ] Specs pass
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by code-simplicity-reviewer during final PR review.
