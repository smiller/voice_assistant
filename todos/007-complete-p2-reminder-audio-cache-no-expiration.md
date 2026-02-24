---
status: pending
priority: p2
issue_id: "007"
tags: [code-review, performance, reliability]
---

# Add expires_in to Reminder Audio Cache Writes

## Problem Statement
`Rails.cache.write("reminder_audio_#{token}", audio)` in `ReminderJob` has no `expires_in` option. Audio entries (20–80 KB each) accumulate indefinitely in Solid Cache and are never evicted by access patterns (they're written once, read once, then dead). At ~100 DAU with 3 reminders/day, the 256MB cache fills in ~17 days, causing continuous LRU eviction churn.

## Findings
- `app/jobs/reminder_job.rb` line 10: `Rails.cache.write(...)` without `expires_in`
- Solid Cache configured with `max_size: 256mb` in `config/cache.yml`
- Entries written once and either read-once or abandoned if browser tab is closed
- After cache fills: continuous write amplification to the database-backed cache store

## Proposed Solutions

### Option A: Add expires_in: 5.minutes (Recommended)
```ruby
Rails.cache.write("reminder_audio_#{token}", audio, expires_in: 5.minutes)
```
5 minutes gives the browser plenty of time to receive the Turbo Stream broadcast and fetch the audio.
- Effort: Small (1 line) | Risk: None

### Option B: expires_in: 1.minute
More aggressive — client typically fetches within seconds of the broadcast.
- Effort: Small | Risk: Very Low

## Acceptance Criteria
- [ ] `Rails.cache.write` in `ReminderJob` includes `expires_in: 5.minutes`
- [ ] ReminderJob spec updated to verify TTL is set
- [ ] Reminder audio delivery still works end-to-end

## Work Log
- 2026-02-23: Identified by performance-oracle during code review
