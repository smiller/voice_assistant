---
status: complete
priority: p1
issue_id: "040"
tags: [code-review, rails, looping-reminders, quality]
dependencies: []
---

# `handle_stop_loop` Uses `find` — Raises RecordNotFound as 500

## Problem Statement

`CommandResponder#handle_stop_loop` calls `user.looping_reminders.find(id)` which raises
`ActiveRecord::RecordNotFound` if the record doesn't exist. There is no rescue clause in
the controller. This produces an unhandled 500 error in production if a stop-loop command
is replayed, arrives after deletion, or is crafted manually.

## Findings

`app/services/command_responder.rb`:
```ruby
def handle_stop_loop(params, user)
  loop = user.looping_reminders.find(params[:looping_reminder_id])
  loop.stop!
```

By contrast, `handle_run_loop` already does this correctly with `find_by` + nil guard:
```ruby
loop = user.looping_reminders.find_by(number: params[:number])
return "Loop #{params[:number]} not found" unless loop
```

The `looping_reminder_id` in params is set by `LoopingReminderDispatcher#match_stop_phrase`
at dispatch time — so in the normal path the record exists. But:
- A replayed `VoiceCommand` with intent `:stop_loop` (e.g., from history playback)
  could reference a deleted reminder
- API callers crafting a text transcript that happens to match a stop phrase from a
  now-deleted loop would trigger a 500

## Proposed Solutions

### Option A: Use `find_by` + nil guard (Recommended)

```ruby
def handle_stop_loop(params, user)
  reminder = user.looping_reminders.find_by(id: params[:looping_reminder_id])
  return "Loop not found" unless reminder
  reminder.stop!
  ...
```

Consistent with `handle_run_loop` and all other not-found paths in the responder.
**Effort:** Trivial
**Risk:** None

### Option B: Rescue `ActiveRecord::RecordNotFound` in the controller

**Cons:** Hides the problem rather than handling it at the right layer
**Risk:** Low but poor practice

## Recommended Action

Option A.

## Technical Details

- `app/services/command_responder.rb` — `handle_stop_loop` method
- `spec/services/command_responder_spec.rb` — add not-found context

## Acceptance Criteria

- [ ] `handle_stop_loop` uses `find_by(id:)` not `find`
- [ ] Returns a user-facing "not found" string (not a 500) if the record is missing
- [ ] Spec covers the not-found path
- [ ] Mutant passes on the new guard

## Work Log

- 2026-02-25: Identified by kieran-rails-reviewer during code review of feat/looping-reminders
