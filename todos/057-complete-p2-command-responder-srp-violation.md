---
status: complete
priority: p2
issue_id: "057"
tags: [code-review, architecture, looping-reminders, refactoring, rails]
dependencies: []
---

# `CommandResponder` Violates Single Responsibility — Mixes Response Text, Broadcasts, and Job Scheduling

## Problem Statement

`CommandResponder` (277 lines) currently handles three distinct concerns:
1. **Response text generation** — `response_text`, `simple_command_text`, `timer_text`, etc.
2. **Turbo Streams broadcasting** — `broadcast_loop_replace`, `broadcast_loop_append`
3. **Job scheduling** — `schedule_reminder`, `schedule_loop_job`
4. **Database mutations** — `create_looping_reminder`, `create_command_alias`

This violates SRP, makes the class hard to test in isolation, and makes it impossible to call response-text logic without triggering side effects. It also requires `include ActionView::RecordIdentifier` in a service object, which bleeds view concerns into the service layer.

## Findings

- `app/services/command_responder.rb:2` — `include ActionView::RecordIdentifier` in a PORO service (view helper mixed in).
- `app/services/command_responder.rb:40-260` — response text methods and broadcast methods interleaved at the same level.
- `app/services/command_responder.rb:81-121` — `schedule_reminder` persists a DB record AND enqueues a job AND broadcasts a Turbo Stream.
- `app/services/command_responder.rb:198-255` — loop creation / alias creation mixed with broadcast side effects.
- Todo 029 (include RecordIdentifier in service — complete) applied a targeted fix, but the broader SRP issue remains.
- Identified by architecture-strategist (P1), kieran-rails-reviewer (P2).

## Proposed Solutions

### Option A: Extract `LoopBroadcaster` service (Recommended)

Move all `Turbo::StreamsChannel.broadcast_*` calls and the `dom_id` dependency into a new `LoopBroadcaster` PORO. `CommandResponder` calls `LoopBroadcaster.new.replace(user, reminder)` etc.

```ruby
class LoopBroadcaster
  include ActionView::RecordIdentifier

  def append(reminder)   = broadcast_append_to(...)
  def replace(user, reminder) = broadcast_replace_to(...)
end
```

**Pros:** Removes `RecordIdentifier` from `CommandResponder`; isolatable; testable with mock.
**Cons:** New file; must wire up in `CommandResponder`.

**Effort:** 2-3 hours
**Risk:** Low

---

### Option B: Extract `ReminderScheduler` service

Move `schedule_reminder` and `schedule_loop_job` into a separate object, leaving `CommandResponder` responsible only for text + Turbo.

**Pros:** Separates persistence from response text.
**Cons:** `CommandResponder` still mixes text and broadcasting.

**Effort:** 2 hours
**Risk:** Low

---

### Option C: Defer — accept current design until tests motivate refactor

`CommandResponder` is not called from multiple callers with conflicting requirements. The SRP violation is a code quality concern, not a correctness bug.

**Pros:** No risk; zero effort.
**Cons:** Technical debt accumulates; class will keep growing.

**Effort:** 0
**Risk:** Low now, higher over time

## Recommended Action

Option A (extract `LoopBroadcaster`) as a first step. Can be done independently of other refactors.

## Technical Details

**Affected files:**
- `app/services/command_responder.rb` — remove broadcast methods and `RecordIdentifier`
- `app/services/loop_broadcaster.rb` — new file
- `spec/services/loop_broadcaster_spec.rb` — new specs
- `spec/services/command_responder_spec.rb` — update stubs

## Acceptance Criteria

- [ ] `ActionView::RecordIdentifier` no longer included in `CommandResponder`
- [ ] Broadcast logic isolated in dedicated class/module
- [ ] All existing specs still pass
- [ ] New specs cover `LoopBroadcaster` in isolation
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by architecture-strategist (P1) and kieran-rails-reviewer (P2) during final PR review.
