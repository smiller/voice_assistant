---
status: complete
priority: p1
issue_id: "037"
tags: [code-review, database, migrations, schema-drift]
dependencies: []
---

# Schema Drift: solid_queue_* Tables in schema.rb Not From This PR's Migrations

## Problem Statement

`schema.rb` in the `feat/looping-reminders` branch contains 11 `solid_queue_*` table
definitions and 6 solid_queue foreign keys that have no corresponding migration files in
this PR. This is local schema drift from the developer's machine. Merging it creates
false history, makes rollbacks dangerous, and will cause merge conflicts when Solid Queue
migrations are properly landed from another branch.

## Findings

PR migrations: only `CreateLoopingReminders`, `CreateCommandAliases`,
`CreatePendingInteractions`. But `schema.rb` also contains:

```
solid_queue_blocked_executions
solid_queue_claimed_executions
solid_queue_failed_executions
solid_queue_jobs
solid_queue_pauses
solid_queue_processes
solid_queue_ready_executions
solid_queue_recurring_executions
solid_queue_recurring_tasks
solid_queue_scheduled_executions
solid_queue_semaphores
```

These tables appear in schema.rb because the developer ran migrations from another branch
locally, then ran this PR's migrations on top. `schema.rb` reflects full local DB state,
not just what this PR introduces.

Risks:
- **Rollback danger**: reverting this PR would roll back `schema.rb` including
  solid_queue table definitions, potentially breaking any other branch that depends on them
- **Merge conflicts**: when the actual Solid Queue migration PR is opened,
  schema.rb will conflict
- **db:schema:load hazard**: anyone running `db:schema:load` from this branch gets
  Solid Queue tables with no migration files, making it impossible to cleanly rollback

## Proposed Solutions

### Option A: Reset schema.rb to main, then re-run PR migrations (Recommended)

```bash
git checkout main -- db/schema.rb
bin/rails db:migrate
git add db/schema.rb
git diff --stat HEAD db/schema.rb  # confirm only 3 PR tables appear
```

**Pros:** Clean schema.rb shows only what this PR actually introduces
**Effort:** Trivial
**Risk:** None — only affects schema.rb, not migration files

### Option B: Accept the drift (Not recommended)

Leave solid_queue tables in schema.rb for this PR.
**Pros:** Zero effort
**Cons:** All risks above remain

## Recommended Action

Option A. Run before opening PR.

## Technical Details

- `db/schema.rb`

## Acceptance Criteria

- [ ] `schema.rb` diff contains only `looping_reminders`, `command_aliases`, and
  `pending_interactions` table additions (and their foreign keys)
- [ ] No `solid_queue_*` tables appear in the PR's schema.rb diff

## Work Log

- 2026-02-25: Identified by schema-drift-detector during code review of feat/looping-reminders
- 2026-02-25: User confirmed solid_queue_* tables came from commit 52f33ed7832faee91d9ce1f89c842dc67d4f0dec (separate from this PR)
