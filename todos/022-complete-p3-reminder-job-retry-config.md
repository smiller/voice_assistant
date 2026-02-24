---
status: pending
priority: p3
issue_id: "022"
tags: [code-review, quality, rails]
dependencies: []
---

# `ReminderJob` Missing `retry_on` / `discard_on` Configuration

## Problem Statement

`ReminderJob` has no `retry_on` or `discard_on` declarations. If `ElevenLabsClient#synthesize` or `Turbo::StreamsChannel.broadcast_append_to` raises an error, Solid Queue will retry the job up to the default limit (25 attempts over 3+ hours). For a reminder that fires at a specific time, retrying hours later is worse than discarding — the user would hear a stale reminder long after they expected it. Additionally, repeated retries against ElevenLabs burn API credits.

## Findings

`app/jobs/reminder_job.rb` has no retry configuration. The job:
1. Calls `ElevenLabsClient#synthesize` (external HTTP, can fail transiently)
2. Writes to `Rails.cache` (in-memory, unlikely to fail)
3. Broadcasts via `Turbo::StreamsChannel` (can fail if Action Cable is down)
4. Updates reminder status to `delivered`

If synthesis fails after the `fire_at` time, a retry is useless to the user.

## Proposed Solutions

### Option A: Discard on any standard error (Recommended)

```ruby
class ReminderJob < ApplicationJob
  discard_on StandardError
```

Fail-fast: if the job can't complete, discard it rather than retrying indefinitely. Log the failure.

**Pros:** Simple, prevents zombie retries, obvious policy
**Cons:** Loses transient-failure resilience (e.g., momentary network blip)
**Effort:** Trivial
**Risk:** Low

### Option B: Retry with short window, then discard

```ruby
retry_on ElevenLabsClient::Error, wait: 30.seconds, attempts: 3
discard_on StandardError
```

Allows 3 quick retries (1.5 minutes) for transient ElevenLabs failures, then discards.

**Pros:** Handles transient errors gracefully
**Cons:** Requires `ElevenLabsClient::Error` domain error class (see todo #019)
**Effort:** Small
**Risk:** Low

## Acceptance Criteria

- [ ] `ReminderJob` has explicit `retry_on` or `discard_on` policy
- [ ] Policy is documented with a comment explaining the rationale
- [ ] Spec verifies the discard behavior for a failing synthesize call

## Work Log

- 2026-02-23: Identified during code review
