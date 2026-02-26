---
status: pending
priority: p2
issue_id: "042"
tags: [code-review, rails, looping-reminders, jobs, reliability]
dependencies: []
---

# `discard_on StandardError` Too Broad in LoopingReminderJob — Chain Dies on Transient Failures

## Problem Statement

`LoopingReminderJob` uses `discard_on StandardError`. Because the job reschedules itself
inside `perform`, any discarded execution permanently terminates the chain — the loop
will be marked `active: true` in the database but will never fire again, with no user
notification and no observability in Solid Queue's failed jobs table. A transient
ElevenLabs timeout silently kills a looping reminder forever.

(Note: `ReminderJob` has the same pattern — see todo #022. This todo covers the new
LoopingReminderJob specifically, where the impact is more severe because of chaining.)

## Findings

`app/jobs/looping_reminder_job.rb` line 5:
```ruby
discard_on StandardError
```

`perform` reschedules on line 22 ONLY if it completes without error:
```ruby
next_fire_at = scheduled_fire_at + loop.interval_minutes.minutes
LoopingReminderJob.set(wait_until: next_fire_at).perform_later(loop.id, next_fire_at)
```

A discarded job never reaches line 22. The chain is dead. Solid Queue's
`solid_queue_failed_executions` will show 0 failures because `discard_on` prevents
records from appearing there.

Spec confirms (but normalises) this behavior:
```ruby
context "when ElevenLabsClient raises an error" do
  it "discards the job without raising" do ...
  it "does not re-enqueue" do ...
```

## Proposed Solutions

### Option A: Targeted discard + retry (Recommended)

```ruby
class LoopingReminderJob < ApplicationJob
  discard_on ActiveRecord::RecordNotFound  # loop was deleted — stop the chain
  retry_on ElevenLabsClient::Error, wait: :polynomially_longer, attempts: 5
  # All other StandardErrors surface to Solid Queue failed_executions for visibility
```

After exhausting retries on `ElevenLabsClient::Error`, add a rescue block that
deactivates the loop and broadcasts a UI notification:
```ruby
rescue_from ElevenLabsClient::Error do |e|
  # After retry exhaustion, Solid Queue calls perform_rescue which calls this
  reminder.update!(active: false)
  Turbo::StreamsChannel.broadcast_replace_to(reminder.user, ...)
end
```

**Pros:** Transient errors heal automatically; permanent ElevenLabs failures deactivate
loop and notify user; unexpected bugs surface visibly in failed_executions
**Effort:** Small
**Risk:** Low — specs need updating but the behavior is strictly better

### Option B: Keep `discard_on StandardError` but add explicit re-enqueue on failure

Rescue in `perform` and always enqueue next iteration:
```ruby
def perform(id, fire_at)
  # ... existing logic
rescue ElevenLabsClient::Error
  # Log but still reschedule
end
LoopingReminderJob.set(...).perform_later(...)  # always runs
```
**Cons:** Hides errors; an infinite crash loop would still enqueue forever
**Risk:** Medium

## Recommended Action

Option A.

## Technical Details

- `app/jobs/looping_reminder_job.rb`
- `spec/jobs/looping_reminder_job_spec.rb` (update discard behavior assertions)

## Acceptance Criteria

- [ ] `discard_on StandardError` removed from `LoopingReminderJob`
- [ ] `discard_on ActiveRecord::RecordNotFound` added (loop deleted mid-chain)
- [ ] `retry_on ElevenLabsClient::Error` added with bounded attempts
- [ ] Spec updated: transient error retries, exhausted retries deactivate loop
- [ ] After N failed retries, loop is deactivated and Turbo broadcast notifies user

## Work Log

- 2026-02-25: Identified by architecture-strategist, security-sentinel, and
  performance-oracle during code review of feat/looping-reminders
