---
status: complete
priority: p2
issue_id: "048"
tags: [code-review, database, looping-reminders, migrations]
dependencies: []
---

# Case-Insensitive Uniqueness Not Enforced at DB Level for Command Aliases and Stop Phrases

## Problem Statement

`CommandAlias` validates `uniqueness: { scope: :user_id, case_sensitive: false }` and
`LoopingReminder` has a unique index on `(user_id, stop_phrase)` — but both indexes are
standard btree (case-sensitive). Under concurrent inserts, "Dishes" and "dishes" can
both pass application-level validation simultaneously and the DB index won't catch it,
creating duplicate entries that bypass the collision logic.

## Findings

Migration `20260226005346_create_command_aliases.rb`:
```ruby
add_index :command_aliases, [ :user_id, :phrase ], unique: true
```

Standard btree index — PostgreSQL btree is case-sensitive. Two concurrent requests
inserting "Dishes" and "dishes" would both pass the model validation (which runs a
`SELECT LOWER(phrase)` query before insert) and both succeed because neither row exists
at validation time. The index won't reject the second because "Dishes" ≠ "dishes" to
PostgreSQL btree.

Same gap exists for `(user_id, stop_phrase)` on `looping_reminders`.

## Proposed Solutions

### Option A: Functional index on `LOWER(phrase)` (Recommended)

Add a new migration with a functional unique index:

```ruby
class AddCaseInsensitiveUniqueIndexToCommandAliasesPhrase < ActiveRecord::Migration[8.1]
  def up
    remove_index :command_aliases, [:user_id, :phrase]
    execute <<~SQL
      CREATE UNIQUE INDEX index_command_aliases_on_user_id_and_lower_phrase
        ON command_aliases (user_id, LOWER(phrase));
    SQL
  end

  def down
    execute "DROP INDEX index_command_aliases_on_user_id_and_lower_phrase"
    add_index :command_aliases, [:user_id, :phrase], unique: true
  end
end
```

Do the same for `looping_reminders.stop_phrase` if not already covered by the
application-level `phrase_taken?` check (it is, but defense-in-depth applies).

**Pros:** Enforces the uniqueness invariant at the database level regardless of
concurrency or application bugs
**Effort:** Small (migration only)
**Risk:** Low — migration replaces the existing index

### Option B: Accept application-level enforcement only

Keep the current indexes. Rely on `phrase_taken?` query and model validation.
**Cons:** Race condition remains under concurrent inserts; not correct in strict DB terms
**Risk:** Low at current single-user scale, higher if multi-user

## Recommended Action

Option A for `command_aliases`. Evaluate `looping_reminders.stop_phrase` — the
`phrase_taken?` guard runs before insert, but the unique index there is also plain btree.
Add the same functional index for defense-in-depth.

## Technical Details

- New migration file
- `db/schema.rb` (updated by migration)

## Acceptance Criteria

- [ ] `command_aliases.phrase` has a functional unique index on `(user_id, LOWER(phrase))`
- [ ] Migration is reversible
- [ ] Old plain btree index removed (replaced by functional index)
- [ ] `CommandAlias` model-level `case_sensitive: false` validation still present (belt + suspenders)

## Work Log

- 2026-02-25: Identified by kieran-rails-reviewer during code review of feat/looping-reminders
