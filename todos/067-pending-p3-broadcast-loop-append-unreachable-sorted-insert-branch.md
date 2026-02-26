---
status: pending
priority: p3
issue_id: "067"
tags: [code-review, quality, looping-reminders, yagni, simplification]
dependencies: []
---

# `broadcast_loop_append` Sorted-Insert Branch Is Unreachable in Production

## Problem Statement

`broadcast_loop_append` queries for a higher-numbered looping reminder to decide between `broadcast_before_to` (insert in order) and `broadcast_append_to` (add at end):

```ruby
def broadcast_loop_append(reminder)
  next_reminder = reminder.user.looping_reminders
                           .where("number > ?", reminder.number)
                           .order(:number).first
  if next_reminder
    Turbo::StreamsChannel.broadcast_before_to(...)
  else
    Turbo::StreamsChannel.broadcast_append_to(...)
  end
end
```

`next_number_for` assigns `max(number) + 1`, so a newly created reminder always has the highest number. No existing reminder has a higher number than a freshly created one. The `broadcast_before_to` branch is therefore never reached via any current command path.

The spec that exercises `broadcast_before_to` stubs `LoopingReminder.next_number_for` to return a gap number — a scenario that cannot arise from any real voice command.

## Findings

- `app/services/command_responder.rb:235-255` — sorted-insert branch
- `app/models/looping_reminder.rb:21` — `next_number_for` always returns `max + 1`
- Spec stubs `next_number_for` to create the gap — unreachable in production
- Identified by code-simplicity-reviewer (YAGNI).

## Proposed Solutions

### Option A: Remove the sorted-insert branch; always `broadcast_append_to` (Recommended)

```ruby
def broadcast_loop_append(reminder)
  Turbo::StreamsChannel.broadcast_append_to(
    reminder.user,
    target: "looping_reminders",
    partial: "looping_reminders/looping_reminder",
    locals: { looping_reminder: reminder }
  )
end
```

Remove the `where("number > ?", ...)` query and the spec stub that exercises the unreachable branch.

**Pros:** -15 lines; eliminates a DB query on every loop creation; honest about actual behaviour.
**Cons:** If number assignment logic ever changes to allow gaps, this would need revisiting.

**Effort:** 30 minutes
**Risk:** Low

---

### Option B: Keep the sorted-insert logic but add a comment explaining it is defensive

**Pros:** No change.
**Cons:** Dead code misleads; extra DB query on every loop creation.

**Effort:** 5 minutes
**Risk:** None

## Recommended Action

Option A. The sorted-insert logic is YAGNI — `next_number_for` guarantees sequential assignment, so the branch cannot be reached.

## Technical Details

**Affected files:**
- `app/services/command_responder.rb:235-255` — simplify method
- `spec/services/command_responder_spec.rb` — remove stub + `broadcast_before_to` shared example invocation for this path

## Acceptance Criteria

- [ ] `broadcast_loop_append` always calls `broadcast_append_to`
- [ ] Extra DB query removed
- [ ] Unreachable spec removed
- [ ] Remaining specs pass; RuboCop clean

## Work Log

- 2026-02-26: Identified by code-simplicity-reviewer during final PR review.
