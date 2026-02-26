---
status: complete
priority: p1
issue_id: "036"
tags: [code-review, security, rails, looping-reminders]
dependencies: []
---

# LoopingReminderJob Writes Wrong Cache Key — Audio Never Served + No Ownership Check

## Problem Statement

`LoopingReminderJob` writes audio under `looping_reminder_audio_#{token}` but
`VoiceAlertsController#show` reads `reminder_audio_#{token}`. Every looping reminder
audio delivery silently returns 404 — the feature does not work at all in production.
Additionally, `VoiceAlertsController` serves audio to any authenticated user who knows
the token, with no ownership check (OWASP A01:2021).

## Findings

`app/jobs/looping_reminder_job.rb` line 13:
```ruby
Rails.cache.write("looping_reminder_audio_#{token}", audio, expires_in: 5.minutes)
```

`app/controllers/voice_alerts_controller.rb` reads:
```ruby
audio = Rails.cache.read("reminder_audio_#{params[:id]}")
```

Two problems:
1. **Functional regression**: the key prefixes don't match, so the cache lookup always
   misses. Looping reminder audio is never played.
2. **Missing ownership check**: the controller doesn't verify the token belongs to
   `current_user`. Any authenticated user who obtains another user's token can read
   their private audio and simultaneously delete the cache entry (denial of service
   against the legitimate user).

## Proposed Solutions

### Option A: Unified key prefix + ownership via cached hash (Recommended)

Store a hash `{ user_id:, audio: }` in the cache so the controller can enforce
ownership before serving bytes. Standardize on a single prefix for all jobs:

```ruby
# In both ReminderJob and LoopingReminderJob:
Rails.cache.write("voice_alert_audio_#{token}", { user_id: user.id, audio: audio },
                  expires_in: 5.minutes)
```

```ruby
# VoiceAlertsController#show:
cached = Rails.cache.read("voice_alert_audio_#{params[:id]}")
return head :not_found unless cached
return head :forbidden unless cached[:user_id] == current_user.id

Rails.cache.delete("voice_alert_audio_#{params[:id]}")
send_data cached[:audio], type: "audio/mpeg", disposition: "inline"
```

**Pros:** Fixes both the functional regression and the ownership gap in one change.
All jobs use the same key prefix, no future prefix drift.
**Effort:** Small
**Risk:** Low (cache key is an implementation detail, no external contract)

### Option B: Separate controller paths per job type

Keep `reminder_audio_` and add a new route/action for `looping_reminder_audio_`.
**Pros:** Minimal change to existing reminder path
**Cons:** Duplicates controller logic; doesn't fix the ownership check gap
**Effort:** Small
**Risk:** Low but leaves ownership gap open

## Recommended Action

Option A.

## Technical Details

- `app/jobs/looping_reminder_job.rb`
- `app/jobs/reminder_job.rb` (needs same key prefix update)
- `app/controllers/voice_alerts_controller.rb`
- `spec/jobs/looping_reminder_job_spec.rb` (update cache key assertions)
- `spec/controllers/voice_alerts_controller_spec.rb` (add ownership test)

## Acceptance Criteria

- [ ] `LoopingReminderJob` and `ReminderJob` use the same cache key prefix
- [ ] `VoiceAlertsController` verifies the cached value's `user_id` matches `current_user`
- [ ] Returns 403 if ownership check fails
- [ ] Spec: authenticated user B cannot fetch user A's audio token
- [ ] Looping reminder audio is actually played in end-to-end test

## Work Log

- 2026-02-25: Identified by security-sentinel during code review of feat/looping-reminders
