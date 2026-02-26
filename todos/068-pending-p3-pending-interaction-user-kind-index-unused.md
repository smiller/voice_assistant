---
status: pending
priority: p3
issue_id: "068"
tags: [code-review, database, looping-reminders, yagni, performance]
dependencies: []
---

# `PendingInteraction` Composite Index on `(user_id, kind)` Is Never Used in Queries

## Problem Statement

The `create_pending_interactions` migration adds a composite index on `(user_id, kind)`:

```ruby
add_index :pending_interactions, [:user_id, :kind]
```

`PendingInteraction.for(user)` queries:
```ruby
where(user: user).active.order(created_at: :asc).first
```

The `active` scope filters on `expires_at > ?`. The `kind` column is never used as a query filter — it is only read after the row is fetched to decide which path to take in `handle_complete_pending`. The composite index therefore provides no query acceleration; it only adds write overhead on every insert.

## Findings

- `db/schema.rb` — `index_pending_interactions_on_user_id_and_kind`
- `app/models/pending_interaction.rb:11` — `PendingInteraction.for(user)` filters on `user_id` + `expires_at`, not `kind`
- `app/services/command_responder.rb:185, 188` — `kind` read after fetch, never used in a `where`
- Identified by code-simplicity-reviewer (YAGNI).

## Proposed Solutions

### Option A: Drop the `(user_id, kind)` index; add `(user_id, expires_at)` instead (Recommended)

```ruby
# Migration
remove_index :pending_interactions, [:user_id, :kind]
add_index :pending_interactions, [:user_id, :expires_at]
```

The real hot query is `WHERE user_id = ? AND expires_at > ?`. A `(user_id, expires_at)` index directly serves this filter.

**Pros:** Removes useless write overhead; adds actually-useful index.
**Cons:** Migration required; minor deploy co-ordination.

**Effort:** 30 minutes
**Risk:** None (table is small; zero data risk)

---

### Option B: Drop the index without replacement

`pending_interactions` is a tiny table (at most a few rows per user). A sequential scan is negligible.

**Pros:** Simplest.
**Cons:** No explicit optimisation if table grows.

**Effort:** 15 minutes
**Risk:** None

## Recommended Action

Option A — replace with a `(user_id, expires_at)` index that matches the actual query.

## Technical Details

**Affected files:**
- `db/migrate/` — new migration

## Acceptance Criteria

- [ ] Old `(user_id, kind)` index removed
- [ ] New `(user_id, expires_at)` index added
- [ ] `db/schema.rb` updated
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by code-simplicity-reviewer during final PR review.
