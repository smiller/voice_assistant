---
status: pending
priority: p3
issue_id: "050"
tags: [code-review, performance, looping-reminders, jobs]
dependencies: []
---

# `clean_expired_interactions` Runs on Every Voice Command — Wrong Layer

## Problem Statement

`LoopingReminderDispatcher#dispatch` calls `clean_expired_interactions(user)` on every
single voice command, issuing a DELETE query even when there are no expired interactions.
The cleanup uses `destroy_all` (which loads objects to fire callbacks) when `delete_all`
would suffice. The `active` scope on `PendingInteraction` already filters by `expires_at`,
so stale rows are already invisible — this cleanup is cosmetic housekeeping on the hot path.

## Findings

`app/services/looping_reminder_dispatcher.rb`:
```ruby
def dispatch(transcript:, user:)
  clean_expired_interactions(user)  # always runs, even with no expired interactions
  ...
end

def clean_expired_interactions(user)
  user.pending_interactions.where("expires_at <= ?", Time.current).destroy_all
  # destroy_all instantiates objects for callbacks; PendingInteraction has none
end
```

`PendingInteraction.for(user)` on the next line already filters by `active` scope
(`where("expires_at > ?", Time.current)`), so expired rows are invisible without cleanup.

## Proposed Solutions

### Option A: Move cleanup to a Solid Queue recurring task (Recommended)

```yaml
# config/recurring.yml (or Solid Queue configuration)
clean_expired_pending_interactions:
  class: CleanExpiredPendingInteractionsJob
  schedule: every 5 minutes
```

Remove `clean_expired_interactions` from `dispatch` entirely.
**Pros:** Cleanup happens off the hot path; doesn't couple routing with housekeeping
**Effort:** Small
**Risk:** Low — stale rows are already invisible to the `active` scope

### Option B: Keep per-request but use `delete_all`

```ruby
def clean_expired_interactions(user)
  user.pending_interactions.where("expires_at <= ?", Time.current).delete_all
end
```

`delete_all` issues one `DELETE WHERE` without instantiating objects. No callbacks are
defined on `PendingInteraction` so no behavior is lost.
**Pros:** Trivial change; still cleans up on every request
**Cons:** Doesn't fix the architectural coupling; still runs on hot path
**Risk:** None

## Recommended Action

Option B immediately (trivial, no risk), then Option A as a follow-up cleanup.

## Technical Details

- `app/services/looping_reminder_dispatcher.rb`
- `app/jobs/clean_expired_pending_interactions_job.rb` (new, if Option A)

## Acceptance Criteria

- [ ] `clean_expired_interactions` uses `delete_all` not `destroy_all`
- [ ] Optionally: cleanup moved to a Solid Queue recurring task
- [ ] All existing dispatcher specs pass

## Work Log

- 2026-02-25: Identified by performance-oracle and architecture-strategist during
  code review of feat/looping-reminders
