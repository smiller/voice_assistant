---
status: complete
priority: p1
issue_id: "053"
tags: [code-review, looping-reminders, jobs, concurrency, correctness]
dependencies: []
---

# Duplicate Job Chains When a Stopped Loop Is Re-Activated

## Problem Statement

When a stopped looping reminder is re-activated with "run loop N", `handle_run_loop` unconditionally calls `schedule_loop_job(reminder)`, injecting a new Solid Queue job into the chain. But the old job chain is not dead — a job was already enqueued at some future `fire_at` when the loop ran last. That job will fire after re-activation, see `active? == true`, deliver a duplicate alert, and schedule a third job. Two independent chains now run in parallel, producing doubled alerts on every interval forever.

## Findings

- `app/services/command_responder.rb:147-155` — `handle_run_loop` calls `reminder.activate!` then `schedule_loop_job(reminder)` unconditionally, regardless of any pre-existing queued jobs.
- `app/jobs/looping_reminder_job.rb:22-23` — job self-schedules with `next_fire_at = scheduled_fire_at + interval_minutes`. The `scheduled_fire_at` argument is the discriminator; the old chain's value differs from the new chain's, so both will run.
- `app/jobs/looping_reminder_job.rb:10` — only guard is `return unless reminder&.active?`. Does not prevent a stale job from running if the loop was re-activated between enqueue and execution.
- Identified by kieran-rails-reviewer (P1), performance-oracle (P1), architecture-strategist (P1), security-sentinel (DoS vector).

## Proposed Solutions

### Option A: Generation/epoch counter on LoopingReminder (Recommended)

Add an integer `job_epoch` column to `looping_reminders`. Increment it on every `activate!`. The job receives the epoch at enqueue time and discards itself if the stored epoch no longer matches.

```ruby
# migration
add_column :looping_reminders, :job_epoch, :integer, default: 0, null: false

# model
def activate!
  update!(active: true, job_epoch: job_epoch + 1)
end

# job
def perform(looping_reminder_id, scheduled_fire_at, expected_epoch)
  reminder = LoopingReminder.find_by(id: looping_reminder_id)
  return unless reminder&.active? && reminder.job_epoch == expected_epoch
  # ...
  LoopingReminderJob.set(wait_until: next_fire_at)
                    .perform_later(reminder.id, next_fire_at, expected_epoch)
end
```

**Pros:** Exact — old chains self-terminate immediately; no race window; no extra DB writes at execution time; epoch persists across restarts.
**Cons:** Schema migration needed; small backwards-compatibility concern if jobs are in-flight during deploy.

**Effort:** 2 hours
**Risk:** Low

---

### Option B: Track `last_scheduled_at` and skip if stale

Record `last_scheduled_at` on the reminder at enqueue time. The job discards if `scheduled_fire_at < last_scheduled_at`.

**Pros:** No separate counter column.
**Cons:** Small race window between `activate!` and the old job's `find_by`; requires careful timestamp precision.

**Effort:** 1.5 hours
**Risk:** Low-Medium

---

### Option C: Cancel old job at stop time via Solid Queue API

When `stop!` is called, cancel any enqueued `LoopingReminderJob` for this reminder via `SolidQueue::Job`.

**Pros:** Eliminates the stale job immediately.
**Cons:** Couples model to job-queue internals; fragile if job is mid-execution; not idempotent.

**Effort:** 3 hours
**Risk:** Medium

## Recommended Action

Implement Option A. The epoch counter is simple, idempotent, and survives deploy-time in-flight jobs gracefully.

## Technical Details

**Affected files:**
- `app/jobs/looping_reminder_job.rb` — add epoch guard
- `app/models/looping_reminder.rb` — increment epoch in `activate!`, pass epoch in `schedule_loop_job`
- `app/services/command_responder.rb:230-233` — `schedule_loop_job` passes epoch
- `db/migrate/` — new migration

**Database changes:** New `job_epoch integer not null default 0` column on `looping_reminders`.

## Acceptance Criteria

- [ ] `activate!` increments `job_epoch`
- [ ] `LoopingReminderJob#perform` exits early if epoch mismatch
- [ ] `schedule_loop_job` passes epoch to `perform_later`
- [ ] Integration spec: stop loop → re-activate → verify only one alert fires per interval
- [ ] Mutant passes on job and model
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by kieran-rails-reviewer, performance-oracle, architecture-strategist, security-sentinel during final PR review.
- 2026-02-26: Fixed via job_epoch counter on LoopingReminder. activate! increments epoch; LoopingReminderJob checks epoch match; schedule_loop_job passes epoch. Migration: add_column :looping_reminders, :job_epoch, integer, default: 0. Also removed dead discard_on RecordNotFound and unused RecordIdentifier include from job (todos 062, 066 partial).
