---
status: pending
priority: p2
issue_id: "059"
tags: [code-review, performance, looping-reminders, database]
dependencies: []
---

# `match_stop_phrase` Loads All Active Loops Into Ruby for Substring Match

## Problem Statement

`LoopingReminderDispatcher#match_stop_phrase` loads every active looping reminder for the user into memory and does a Ruby-level `include?` check. For a user with many active loops this is O(n) Ruby allocations plus O(n × m) string operations (where m is transcript length). The check runs on **every single voice command**, including time checks and timer commands that have nothing to do with loops.

A database-side `LOWER(stop_phrase)` substring query would eliminate the Ruby iteration entirely and leverage the index on the column.

## Findings

- `app/services/looping_reminder_dispatcher.rb:25-29`:
  ```ruby
  def match_stop_phrase(transcript, user)
    user.looping_reminders.active_loops.find do |lr|
      transcript.downcase.include?(lr.stop_phrase.downcase)
    end
  end
  ```
  Full `active_loops` relation materialized into Ruby; `find` iterates until match.
- `app/models/looping_reminder.rb:10` — `scope :active_loops, -> { where(active: true) }` — no index on `active`.
- `db/schema.rb` — no index on `looping_reminders.active`.
- Identified by performance-oracle (P1 — hot path on every request).

## Proposed Solutions

### Option A: Push substring match to DB with `LIKE` query (Recommended)

```ruby
def match_stop_phrase(transcript, user)
  normalized = transcript.downcase
  user.looping_reminders
      .active_loops
      .where("? LIKE '%' || LOWER(stop_phrase) || '%'", normalized)
      .first
end
```

PostgreSQL evaluates the predicate in the DB; only matching rows are loaded.

**Pros:** No Ruby iteration; scales linearly with number of loops (index scan possible with prefix index); transcript never leaves the query.
**Cons:** SQL is less readable; PostgreSQL-specific `||` concatenation (acceptable given existing LOWER() usage throughout codebase).

**Effort:** 1 hour
**Risk:** Low — same semantics, just pushed to DB

---

### Option B: Add index on `looping_reminders.active` + keep Ruby iteration

A partial index `WHERE active = true` reduces the rows loaded but doesn't eliminate Ruby iteration.

**Pros:** Simple migration.
**Cons:** Doesn't fix Ruby allocation; only a minor improvement.

**Effort:** 30 minutes
**Risk:** Low

---

### Option C: Normalize stop phrases into a separate indexed lookup table

Premature optimization for current scale.

**Effort:** Large
**Risk:** High complexity

## Recommended Action

Option A (DB-side `LIKE`) combined with a partial index on `active = true` (Option B). Together they make the query fast and server-side.

## Technical Details

**Affected files:**
- `app/services/looping_reminder_dispatcher.rb:25-29`
- `db/migrate/` — add `add_index :looping_reminders, :active, where: "active = true"`

## Acceptance Criteria

- [ ] `match_stop_phrase` does not materialize Ruby array; uses `first` on an AR relation
- [ ] Spec verifies correct match semantics (case-insensitive, substring)
- [ ] Partial index migration added
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by performance-oracle during final PR review.
