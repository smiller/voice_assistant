---
status: pending
priority: p2
issue_id: "055"
tags: [code-review, agent-native, api, looping-reminders]
dependencies: []
---

# No API Endpoint to Inspect Pending Interactions

## Problem Statement

When a loop creation or alias command fails because a phrase is already taken, the system creates a `PendingInteraction` and responds with a TTS prompt asking the user to supply a replacement phrase. This multi-turn dialogue state is invisible to agents: there is no REST endpoint to check whether a `PendingInteraction` is currently waiting. An agent that submits a text command and receives a "phrase already in use" response has no way to subsequently inspect the pending state, confirm it is still active, or introspect the context without issuing another text command.

## Findings

- `app/models/pending_interaction.rb` — `PendingInteraction.for(user)` scoped query, but no controller exposes this.
- `app/controllers/api/v1/` — only `LoopingRemindersController` (index) and `TextCommandsController` (create). No pending interactions endpoint.
- `app/services/looping_reminder_dispatcher.rb:5-6` — pending interaction consumed silently on next `dispatch` call; agent must guess state.
- Identified by agent-native-reviewer (P1 — blocks multi-turn agent workflows).

## Proposed Solutions

### Option A: Add `GET /api/v1/pending_interaction` endpoint (Recommended)

Returns the active pending interaction for the authenticated user (or 204 if none).

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resource :pending_interaction, only: [:show]
  end
end

# app/controllers/api/v1/pending_interactions_controller.rb
module Api
  module V1
    class PendingInteractionsController < BaseController
      def show
        pending = PendingInteraction.for(@current_user)
        if pending
          render json: { kind: pending.kind, context: pending.context, expires_at: pending.expires_at }
        else
          head :no_content
        end
      end
    end
  end
end
```

**Pros:** Agent can poll before sending follow-up; simple read-only endpoint; no state mutation.
**Cons:** Agent must still send a text command to supply the replacement phrase; slight proliferation of endpoints.

**Effort:** 1 hour
**Risk:** Low

---

### Option B: Include pending interaction in text command response JSON

When a text command results in a pending interaction, return the pending state in the response body alongside the audio.

**Pros:** Single round-trip.
**Cons:** Audio/JSON response mixing is awkward; changes existing API shape.

**Effort:** 2 hours
**Risk:** Medium

## Recommended Action

Option A. Minimal surface area, zero risk, enables clean agent multi-turn orchestration.

## Technical Details

**Affected files:**
- `config/routes.rb` — add singular resource
- `app/controllers/api/v1/pending_interactions_controller.rb` — new controller
- `spec/controllers/api/v1/pending_interactions_controller_spec.rb` — specs

## Acceptance Criteria

- [ ] `GET /api/v1/pending_interaction` returns 200 with kind/context/expires_at when pending
- [ ] Returns 204 when no pending interaction
- [ ] Returns 401 for unauthenticated requests
- [ ] Specs added; RuboCop clean

## Work Log

- 2026-02-26: Identified by agent-native-reviewer during final PR review.
