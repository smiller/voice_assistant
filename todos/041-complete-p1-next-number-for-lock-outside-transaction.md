---
status: complete
priority: p1
issue_id: "041"
tags: [code-review, rails, looping-reminders, database, concurrency]
dependencies: []
---

# `LoopingReminder.next_number_for` Lock Is Outside a Transaction — Race Condition

## Problem Statement

`LoopingReminder.next_number_for(user)` uses `SELECT ... FOR UPDATE` (`.lock`) to
prevent concurrent reads of the same max number. However, the lock is meaningless
without a wrapping transaction: the lock is held only for the duration of the SELECT,
released immediately, and the subsequent `create!` runs in a separate transaction.
Two concurrent `create_loop` requests can both read the same max, compute the same
next number, and one will get `ActiveRecord::RecordNotUnique` — an unhandled 500.

## Findings

`app/models/looping_reminder.rb`:
```ruby
def self.next_number_for(user)
  (user.looping_reminders.lock.pluck(:number).max || 0) + 1
end
```

Call sites in `CommandResponder#handle_create_loop` and `handle_complete_pending`:
```ruby
loop = LoopingReminder.create!(user: user,
  number: LoopingReminder.next_number_for(user), ...)
```

The `create!` is in a separate Rails auto-transaction, not the same transaction as the
`.lock`. `SELECT FOR UPDATE` only blocks concurrent transactions from locking the same
rows — it doesn't prevent a concurrent request from running `next_number_for` before
this transaction commits its new row. The unique index on `(user_id, number)` will
catch the duplicate, but as an unhandled exception.

Additionally, `pluck(:number).max` loads all numbers into Ruby to call `.max`. Use
`maximum(:number)` instead for a single-value aggregate.

## Proposed Solutions

### Option A: Wrap the read + create in an explicit transaction (Recommended)

```ruby
# app/services/command_responder.rb — handle_create_loop and handle_complete_pending
ActiveRecord::Base.transaction do
  number = LoopingReminder.next_number_for(user)
  LoopingReminder.create!(user: user, number: number, ...)
end
```

And update `next_number_for` to use the proper aggregate:
```ruby
def self.next_number_for(user)
  (user.looping_reminders.lock.maximum(:number) || 0) + 1
end
```

Inside the transaction, the `FOR UPDATE` lock on the aggregate row is held until the
transaction commits, preventing concurrent readers from computing the same next number.

**Pros:** Correct concurrency semantics; fixes the race
**Effort:** Small
**Risk:** Low — wraps existing code in a transaction

### Option B: Rescue `ActiveRecord::RecordNotUnique` and retry

Catch the uniqueness violation and retry with a fresh number lookup.
**Cons:** Retries add latency; still a code smell
**Risk:** Medium (infinite loop if bug causes persistent collisions)

## Recommended Action

Option A.

## Technical Details

- `app/models/looping_reminder.rb` — `next_number_for`
- `app/services/command_responder.rb` — `handle_create_loop`, `handle_complete_pending`
- `spec/services/command_responder_spec.rb` — add concurrent creation test

## Acceptance Criteria

- [ ] `next_number_for` uses `maximum(:number)` not `pluck(:number).max`
- [ ] Both `handle_create_loop` and `handle_complete_pending` wrap number read + create
  in `ActiveRecord::Base.transaction`
- [ ] The `lock` call is inside the transaction
- [ ] Mutant passes on `next_number_for`

## Work Log

- 2026-02-25: Identified by kieran-rails-reviewer and performance-oracle during
  code review of feat/looping-reminders
