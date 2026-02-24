---
status: pending
priority: p3
issue_id: "024"
tags: [code-review, quality, rails]
dependencies: []
---

# Dead `VoiceCommand` Enum Values (`:scheduled`, `:failed`)

## Problem Statement

The `VoiceCommand` model defines `status` enum values `:scheduled` and `:failed` that are never written anywhere in the codebase. Only `:pending`, `:processing`, and `:completed` are used by the controller. Dead enum values add confusion ("is this used somewhere?"), inflate the schema, and waste database index space if the column is indexed.

## Findings

In `app/models/voice_command.rb` (or the migration), enum likely includes:

```ruby
enum :status, { pending: 0, processing: 1, completed: 2, scheduled: 3, failed: 4 }
```

A grep of the codebase finds no writes of `.scheduled!` or `.failed!` and no reads of `.scheduled?` or `.failed?`. They were presumably added speculatively.

## Proposed Solutions

### Option A: Remove unused enum values via migration (Recommended)

Write a migration that doesn't change the column storage (values 0/1/2 remain), just removes the unused enum declarations from the model. If values 3/4 appear in production data, investigate before removing.

```ruby
# In the model — remove :scheduled and :failed
enum :status, { pending: 0, processing: 1, completed: 2 }
```

**Pros:** Clean model, no dead code
**Cons:** Must verify values 3/4 are absent in production data first
**Effort:** Small
**Risk:** Low (check production data first)

### Option B: Keep but add a comment

```ruby
# :scheduled and :failed reserved for future async pipeline; not yet used
```

**Pros:** Zero risk
**Cons:** Still dead code; comment will likely rot
**Effort:** Trivial
**Risk:** None

## Acceptance Criteria

- [ ] Unused enum values removed (or explicitly documented with rationale)
- [ ] Confirmed values 3/4 absent in production data before removal
- [ ] Specs and RuboCop clean

## Work Log

- 2026-02-23: Identified during code review
