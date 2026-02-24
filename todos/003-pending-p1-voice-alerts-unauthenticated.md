---
status: pending
priority: p1
issue_id: "003"
tags: [code-review, security, access-control]
---

# Add Authentication Guard to VoiceAlertsController

## Problem Statement
`VoiceAlertsController#show` has no `before_action :require_authentication`. Any unauthenticated HTTP client that learns a token can: (1) retrieve another user's private audio reminder, and (2) simultaneously destroy the cache entry so the legitimate user never hears it. This is both a privacy violation and a denial-of-service against reminder delivery.

## Findings
- `app/controllers/voice_alerts_controller.rb`: no `before_action :require_authentication`
- `app/controllers/application_controller.rb` already defines `require_authentication`
- Token is 32 hex chars (strong entropy) — security through obscurity, not explicit auth
- Cache entry deleted on read (`Rails.cache.delete`) — interception destroys delivery
- Multi-user scenario: cross-user audio access

## Proposed Solutions

### Option A: Add before_action (Recommended)
```ruby
class VoiceAlertsController < ApplicationController
  before_action :require_authentication

  def show
    audio = Rails.cache.read("reminder_audio_#{params[:id]}")
    ...
  end
end
```
- Effort: Small | Risk: None

### Option B: Add auth + user-scoping
Also verify the reminder token belongs to current_user before serving. Requires storing user_id alongside the token in cache.
- Effort: Medium | Risk: Low | More secure

## Acceptance Criteria
- [ ] `before_action :require_authentication` added to `VoiceAlertsController`
- [ ] Unauthenticated request returns 302 redirect (or 401), not audio
- [ ] Existing authenticated reminder delivery still works

## Work Log
- 2026-02-23: Identified by rails-reviewer, security-sentinel, architecture-strategist, simplicity-reviewer
