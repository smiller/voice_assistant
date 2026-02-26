---
status: pending
priority: p3
issue_id: "063"
tags: [code-review, agent-native, api, looping-reminders]
dependencies: []
---

# Agent CRUD for Looping Reminders Is Incomplete — No PATCH or DELETE

## Problem Statement

Todo 049 added `GET /api/v1/looping_reminders` (index). However, agents cannot modify loop settings (interval, message, stop phrase) or delete a loop via the API. The only mutation available is stop/activate via a text command. For programmatic agent workflows — e.g. an agent that wants to clean up all loops for a user, or adjust an interval — there is no direct REST path.

## Findings

- `app/controllers/api/v1/looping_reminders_controller.rb` — only `index` action; no `update` or `destroy`.
- `config/routes.rb` — likely only `only: [:index]` for this resource.
- Identified by agent-native-reviewer (P2).

## Proposed Solutions

### Option A: Add `destroy` endpoint (Recommended first step)

```ruby
# config/routes.rb
resources :looping_reminders, only: [:index, :destroy]

# app/controllers/api/v1/looping_reminders_controller.rb
def destroy
  reminder = @current_user.looping_reminders.find(params[:id])
  reminder.destroy!
  head :no_content
end
```

**Pros:** Enables agent cleanup; simple; `destroy!` cascades `command_aliases`.
**Cons:** Irreversible; caller must confirm intent.

**Effort:** 1 hour
**Risk:** Low

---

### Option B: Add `update` endpoint for stop/activate/interval changes

Allow PATCH to change `active`, `interval_minutes`, etc.

**Pros:** Full CRUD parity.
**Cons:** More surface area; need validation of which fields are user-editable.

**Effort:** 2 hours
**Risk:** Low

---

### Option C: Defer until agent use cases demand it

Voice command path can stop/activate loops today. Delete is uncommon.

**Effort:** 0
**Risk:** None now

## Recommended Action

Option A (delete) as minimum. Option B (update) if agent use cases emerge.

## Technical Details

**Affected files:**
- `app/controllers/api/v1/looping_reminders_controller.rb`
- `config/routes.rb`
- `spec/controllers/api/v1/looping_reminders_controller_spec.rb`

## Acceptance Criteria

- [ ] `DELETE /api/v1/looping_reminders/:id` returns 204 on success
- [ ] Returns 404 for unknown ID or other user's loop
- [ ] Cascades deletion of `command_aliases`
- [ ] Spec covers success + not-found
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by agent-native-reviewer during final PR review.
