---
status: pending
priority: p2
issue_id: "061"
tags: [code-review, performance, looping-reminders, database, quality]
dependencies: []
---

# `next_number_for` Uses `lock.pluck(:number).max` Instead of `maximum(:number)`

## Problem Statement

`LoopingReminder.next_number_for(user)` loads all loop number values from the database into a Ruby array to find the maximum:

```ruby
(user.looping_reminders.lock.pluck(:number).max || 0) + 1
```

`pluck(:number)` materialises all `number` values into Ruby memory, then Ruby's `Enumerable#max` iterates them. For a user with many loops this is needlessly verbose. `maximum(:number)` pushes the `MAX()` aggregate into SQL, returning a single value — exactly one row transfer instead of n rows.

## Findings

- `app/models/looping_reminder.rb:21` — `user.looping_reminders.lock.pluck(:number).max`
- The `.lock` (SELECT FOR UPDATE) is correct and must be preserved.
- Identified by performance-oracle (P2), kieran-rails-reviewer (P3).

## Proposed Solutions

### Option A: Replace `pluck(:number).max` with `maximum(:number)` (Recommended)

```ruby
def self.next_number_for(user)
  (user.looping_reminders.lock.maximum(:number) || 0) + 1
end
```

`ActiveRecord::Calculations#maximum` generates `SELECT MAX(number) FROM looping_reminders WHERE ... FOR UPDATE`.

**Pros:** Single scalar returned from DB; fewer allocations; identical semantics; preserves lock.
**Cons:** None.

**Effort:** 5 minutes
**Risk:** None — identical result

## Recommended Action

Option A.

## Technical Details

**Affected files:**
- `app/models/looping_reminder.rb:21`
- `spec/models/looping_reminder_spec.rb` — existing spec covers `next_number_for`; no change needed unless mutant demands it

## Acceptance Criteria

- [ ] `pluck(:number).max` replaced with `maximum(:number)`
- [ ] Existing `next_number_for` spec still passes
- [ ] Mutant passes on `LoopingReminder.next_number_for`
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by performance-oracle (P2) and kieran-rails-reviewer (P3) during final PR review.
