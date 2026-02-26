---
status: pending
priority: p3
issue_id: "049"
tags: [code-review, agent-native, api, looping-reminders]
dependencies: [027]
---

# No `GET /api/v1/looping_reminders` — Agents Can't Discover Loop State

## Problem Statement

An agent can issue all looping reminder voice commands via `POST /api/v1/text_commands`,
but cannot enumerate what loops exist, their numbers, stop phrases, or active state.
Without a read endpoint, an agent must guess loop numbers and can't verify success.

(Extends existing todo #027 — agent-native gaps — specifically for looping reminders.)

## Findings

From agent-native-reviewer:
- `VoiceCommandsController#index` loads `@looping_reminders` but renders HTML only
- No `GET /api/v1/looping_reminders` exists
- Agent targeting `run loop N` or `stop_loop` must know the number out of band
- Multi-turn pending interaction state also has no read endpoint — an agent can't check
  whether it's in the middle of a phrase-collision dialogue

## Proposed Solutions

### Option A: `GET /api/v1/looping_reminders` returning JSON (Recommended)

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :looping_reminders, only: [:index]
  end
end

# app/controllers/api/v1/looping_reminders_controller.rb
class Api::V1::LoopingRemindersController < Api::V1::BaseController
  def index
    render json: current_user.looping_reminders
                             .includes(:command_aliases)
                             .order(:number)
                             .map { |lr|
      {
        id: lr.id, number: lr.number, message: lr.message,
        stop_phrase: lr.stop_phrase, interval_minutes: lr.interval_minutes,
        active: lr.active,
        aliases: lr.command_aliases.map(&:phrase),
        pending_interaction: PendingInteraction.for(current_user)&.kind
      }
    }
  end
end
```

**Pros:** Agents can discover loop state before acting; full action parity
**Effort:** Medium
**Risk:** Low

### Option B: Add looping reminders to existing text_commands response

Include state in the text_commands response metadata. Couples unrelated concerns.
**Effort:** Small
**Risk:** Low but poor design

## Recommended Action

Option A. Resolve todo #027 (general text API + token auth) first as a prerequisite.

## Technical Details

- `config/routes.rb`
- `app/controllers/api/v1/looping_reminders_controller.rb` (new)
- `spec/controllers/api/v1/looping_reminders_controller_spec.rb` (new)

## Acceptance Criteria

- [ ] `GET /api/v1/looping_reminders` returns JSON array with number, message,
  stop_phrase, interval_minutes, active, aliases
- [ ] Endpoint requires Bearer token auth (not cookie)
- [ ] Only returns the authenticated user's loops (no IDOR)
- [ ] Spec covers authenticated and unauthenticated access

## Work Log

- 2026-02-25: Identified by agent-native-reviewer during code review of feat/looping-reminders
