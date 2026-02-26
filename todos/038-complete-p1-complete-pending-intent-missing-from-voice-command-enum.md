---
status: complete
priority: p1
issue_id: "038"
tags: [code-review, rails, looping-reminders, database]
dependencies: []
---

# `complete_pending` Intent Missing From VoiceCommand Enum — Will Raise in Production

## Problem Statement

`LoopingReminderDispatcher` can return `intent: :complete_pending` which both
controllers pass to `VoiceCommand.create!(intent: ...)`. But `:complete_pending` is
not in the `VoiceCommand` enum. This will raise `ArgumentError: 'complete_pending'
is not a valid intent` in production every time a user completes a pending interaction
(e.g., provides a replacement stop phrase after a collision).

## Findings

`app/models/voice_command.rb` enum:
```ruby
enum :intent, {
  time_check: "time_check", sunset: "sunset", timer: "timer",
  reminder: "reminder", daily_reminder: "daily_reminder",
  create_loop: "create_loop", run_loop: "run_loop",
  alias_loop: "alias_loop", stop_loop: "stop_loop",
  give_up: "give_up", unknown: "unknown"
}
```

Missing: `complete_pending`.

`app/services/looping_reminder_dispatcher.rb` line 52:
```ruby
{ intent: :complete_pending, params: context.merge(...) }
```

Both `VoiceCommandsController#create` and `Api::V1::TextCommandsController#create`
call `VoiceCommand.create!(intent: parsed[:intent], ...)` unconditionally.

## Proposed Solutions

### Option A: Add `:complete_pending` to the enum (Recommended)

```ruby
# app/models/voice_command.rb
complete_pending: "complete_pending",
```

Also requires a migration to add the new value to the database column if it's a
string enum (it is — Rails uses string values here, so no migration needed for
PostgreSQL string enum, just the model change).

**Pros:** Simple, correct, consistent with how all other intents work
**Effort:** Trivial
**Risk:** None

### Option B: Map `complete_pending` to `:unknown` before creating VoiceCommand

Filter out `complete_pending` from the intent stored in the VoiceCommand record.
**Pros:** No enum change
**Cons:** Loses audit trail of pending-interaction completions; misleading
**Risk:** Low

## Recommended Action

Option A.

## Technical Details

- `app/models/voice_command.rb`
- `spec/models/voice_command_spec.rb` (add complete_pending to enum assertion)

## Acceptance Criteria

- [ ] `:complete_pending` is in the `VoiceCommand` enum
- [ ] `spec/models/voice_command_spec.rb` enum test includes `complete_pending`
- [ ] No `ArgumentError` when completing a pending interaction end-to-end
- [ ] Mutant still passes on VoiceCommand

## Work Log

- 2026-02-25: Identified by kieran-rails-reviewer during code review of feat/looping-reminders
