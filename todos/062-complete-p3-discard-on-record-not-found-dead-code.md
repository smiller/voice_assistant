---
status: pending
priority: p3
issue_id: "062"
tags: [code-review, looping-reminders, quality, jobs]
dependencies: []
---

# `discard_on ActiveRecord::RecordNotFound` Is Dead Code in `LoopingReminderJob`

## Problem Statement

`LoopingReminderJob` declares `discard_on ActiveRecord::RecordNotFound` but the job uses `find_by(id:)` which returns `nil` rather than raising. `RecordNotFound` can never be raised in `perform`, so the `discard_on` handler is unreachable and misleads readers into thinking it provides safety that it does not.

This dead code was introduced when todo 040 changed `find` → `find_by` but left the `discard_on` declaration in place.

## Findings

- `app/jobs/looping_reminder_job.rb:5` — `discard_on ActiveRecord::RecordNotFound`
- `app/jobs/looping_reminder_job.rb:9` — `LoopingReminder.find_by(id: looping_reminder_id)` — returns nil, never raises
- `app/jobs/looping_reminder_job.rb:10` — `return unless reminder&.active?` — guards against nil
- No code path in `perform` raises `RecordNotFound`.
- Identified by kieran-rails-reviewer (P1 — dead code masking intent), performance-oracle (P3).

## Proposed Solutions

### Option A: Remove `discard_on ActiveRecord::RecordNotFound` (Recommended)

```ruby
class LoopingReminderJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :default
  retry_on ElevenLabsClient::Error, wait: :polynomially_longer, attempts: 5
  # discard_on removed — find_by returns nil, RecordNotFound never raised
```

**Pros:** Removes misleading dead code; makes the nil-guard on line 10 the single source of truth.
**Cons:** None.

**Effort:** 5 minutes
**Risk:** None — the `discard_on` was unreachable anyway

## Recommended Action

Option A.

## Technical Details

**Affected files:**
- `app/jobs/looping_reminder_job.rb:5`

## Acceptance Criteria

- [ ] `discard_on ActiveRecord::RecordNotFound` removed
- [ ] Job specs still pass
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by kieran-rails-reviewer during final PR review. Root cause: todo 040 changed `find` → `find_by` but did not remove the corresponding `discard_on`.
