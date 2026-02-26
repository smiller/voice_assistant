---
status: pending
priority: p3
issue_id: "064"
tags: [code-review, agent-native, api, looping-reminders, jobs]
dependencies: []
---

# Looping Reminder Alerts Are Delivered via Turbo Only — No Agent Polling Endpoint

## Problem Statement

`LoopingReminderJob` delivers alerts exclusively by broadcasting a Turbo Stream to the user's ActionCable channel. An agent using the REST API has no way to receive fired loop alerts: there is no polling endpoint that returns pending alerts, and the agent cannot listen to ActionCable. The agent submits a text command and hears the confirmation, but when the interval fires, the audio is only delivered to a browser session. Agent workflows that depend on being notified when an interval fires cannot work with the current design.

## Findings

- `app/jobs/looping_reminder_job.rb:15-20` — `Turbo::StreamsChannel.broadcast_append_to` writes a `voice_alerts` partial to the browser DOM; no REST side-channel.
- No `GET /api/v1/alerts` or equivalent endpoint exists.
- `app/controllers/api/v1/` — only `looping_reminders` (index) and `text_commands` (create).
- Identified by agent-native-reviewer (P1).

## Proposed Solutions

### Option A: Persist alerts to a `VoiceAlert` model + polling endpoint

Create a lightweight `voice_alerts` table. `LoopingReminderJob` writes a row; Turbo broadcasts to browser; agent polls `GET /api/v1/voice_alerts` and marks alerts read.

```ruby
# GET /api/v1/voice_alerts — returns unread alerts; DELETE :id marks read
class Api::V1::VoiceAlertsController < BaseController
  def index
    render json: @current_user.voice_alerts.unread.order(created_at: :asc)
  end

  def destroy
    alert = @current_user.voice_alerts.find(params[:id])
    alert.update!(read_at: Time.current)
    head :no_content
  end
end
```

**Pros:** Clean dual delivery (Turbo + REST); agent-native parity; alerts survive connection drops.
**Cons:** New table and migration; changes to job; more complexity.

**Effort:** 4-6 hours
**Risk:** Low-Medium

---

### Option B: Return audio bytes in a polling endpoint using existing cache

Reuse the existing `Rails.cache.write("voice_alert_#{user.id}_#{token}", audio)` pattern. Add `GET /api/v1/voice_alerts/pending` that returns the token(s), and `GET /api/v1/voice_alerts/:token` that returns the audio bytes and then expires the cache entry.

**Pros:** No new table; leverages existing cache write; low schema impact.
**Cons:** Cache-backed (ephemeral, lost on restart); 5-minute window hard-coded; agents must poll rapidly.

**Effort:** 2 hours
**Risk:** Low

---

### Option C: Defer

Browser is the primary consumer of looping reminder alerts; agent use case is low priority today.

**Effort:** 0
**Risk:** Low now

## Recommended Action

Option B as a fast first step (leverages existing cache infrastructure). Option A if agent-native parity becomes a product priority.

## Technical Details

**Affected files:**
- `app/controllers/api/v1/` — new alerts controller
- `config/routes.rb`
- Possibly `app/jobs/looping_reminder_job.rb` — write alert record

## Acceptance Criteria

- [ ] Agent can retrieve pending loop alert tokens or audio via REST
- [ ] Alerts expire after delivery (not polled twice)
- [ ] Turbo delivery to browser unaffected
- [ ] Spec covers alert retrieval and expiry
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by agent-native-reviewer during final PR review.
