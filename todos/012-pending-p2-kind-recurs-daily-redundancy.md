---
status: pending
priority: p2
issue_id: "012"
tags: [code-review, architecture, data-integrity]
---

# Resolve kind/recurs_daily Redundancy on Reminder Model

## Problem Statement
`Reminder` has both a `kind` enum (`daily_reminder` value) and a `recurs_daily` boolean. These carry identical information and must always agree, but no validation enforces the invariant. A `daily_reminder` record with `recurs_daily: false` is representable in the database and would silently break the recurrence chain in `ReminderJob`.

## Findings
- `app/models/reminder.rb`: both `enum :kind` and `boolean recurs_daily` present
- `app/jobs/reminder_job.rb` line 19: checks `reminder.recurs_daily?`
- `app/services/command_responder.rb` line 58: sets `recurs = command[:intent] == :daily_reminder`
- No validation enforcing `kind == "daily_reminder" ↔ recurs_daily == true`

## Proposed Solutions

### Option A: Add validation invariant (Recommended)
```ruby
validates :recurs_daily, inclusion: { in: [true] }, if: :daily_reminder?
validates :recurs_daily, inclusion: { in: [false] }, unless: :daily_reminder?
```
Keeps both fields but enforces agreement.
- Effort: Small | Risk: None

### Option B: Remove recurs_daily, derive from kind
Replace all `reminder.recurs_daily?` calls with `reminder.daily_reminder?`. Drop the column in a migration.
- Effort: Medium | Risk: Low (removes redundancy entirely)
- Cleaner long-term

## Acceptance Criteria
- [ ] A `Reminder` with `kind: :daily_reminder, recurs_daily: false` cannot be persisted
- [ ] A `Reminder` with `kind: :reminder, recurs_daily: true` cannot be persisted
- [ ] Existing tests and job behavior unchanged

## Work Log
- 2026-02-23: Identified by architecture-strategist during code review
