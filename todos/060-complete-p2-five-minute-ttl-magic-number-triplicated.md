---
status: complete
priority: p2
issue_id: "060"
tags: [code-review, looping-reminders, quality, constants]
dependencies: []
---

# 5-Minute Pending Interaction TTL Magic Number Appears Three Times

## Problem Statement

The `5.minutes.from_now` TTL for `PendingInteraction` is hard-coded in three separate places. If the timeout is changed, all three sites must be updated. The constant has business meaning — it's the window in which a user must respond when a phrase is already taken — and deserves a named constant.

## Findings

- `app/services/command_responder.rb:130` — `expires_at: 5.minutes.from_now` in `handle_create_loop`
- `app/services/command_responder.rb:174` — `expires_at: 5.minutes.from_now` in `handle_alias_loop`
- `app/services/looping_reminder_dispatcher.rb:47` — `expires_at: 5.minutes.from_now` in `handle_pending_interaction` (TTL extension on phrase-conflict retry)
- Identified by architecture-strategist (P2).

## Proposed Solutions

### Option A: Named constant on `PendingInteraction` model (Recommended)

```ruby
# app/models/pending_interaction.rb
INTERACTION_TTL = 5.minutes

# Usage in CommandResponder and LoopingReminderDispatcher:
expires_at: PendingInteraction::INTERACTION_TTL.from_now
```

**Pros:** Single source of truth; self-documenting; zero behaviour change.
**Cons:** Cross-service coupling to a model constant (acceptable — it's the owning model).

**Effort:** 30 minutes
**Risk:** None

---

### Option B: Module-level constant in a shared concern

Define `PENDING_INTERACTION_TTL` in `ApplicationRecord` or a `LoopConstants` module.

**Pros:** Avoids coupling services to model.
**Cons:** Overkill; adds indirection without benefit at current scale.

**Effort:** 45 minutes
**Risk:** None

## Recommended Action

Option A.

## Technical Details

**Affected files:**
- `app/models/pending_interaction.rb` — add `INTERACTION_TTL = 5.minutes`
- `app/services/command_responder.rb:130, 174`
- `app/services/looping_reminder_dispatcher.rb:47`

## Acceptance Criteria

- [ ] `5.minutes.from_now` replaced with `PendingInteraction::INTERACTION_TTL.from_now` in all three sites
- [ ] Constant defined on `PendingInteraction`
- [ ] Existing specs still pass (no behaviour change)
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by architecture-strategist during final PR review.
