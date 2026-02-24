---
status: pending
priority: p2
issue_id: "011"
tags: [code-review, database, schema]
---

# Add Missing DB Constraints and Indexes

## Problem Statement
Several columns have model-level validations but no database-level enforcement, and critical query columns lack indexes. These gaps allow invalid data at the DB level and will cause full table scans as the reminders table grows.

## Findings
- `db/schema.rb`: `reminders.fire_at` is nullable despite `validates :fire_at, presence: true`
- `db/schema.rb`: `voice_commands.status` nullable, no default, despite `validates :status, presence: true`
- `db/schema.rb`: `voice_commands.intent` nullable, no default
- No index on `reminders (status, fire_at)` — natural query for pending reminders due to fire
- No index on `voice_commands.status` or `voice_commands.intent`
- `reminders.status` has no index (only `user_id` and `voice_command_id` are indexed)

## Proposed Solutions

### Option A: Migration with constraints + indexes (Recommended)
```ruby
def change
  change_column_null :reminders, :fire_at, false
  change_column_null :voice_commands, :status, false
  change_column_default :voice_commands, :status, "received"
  change_column_null :voice_commands, :intent, false
  change_column_default :voice_commands, :intent, "unknown"
  add_index :reminders, [:status, :fire_at]
  add_index :voice_commands, :status
end
```
- Effort: Small | Risk: Low (requires existing data to be clean)

## Acceptance Criteria
- [ ] `reminders.fire_at` is NOT NULL
- [ ] `voice_commands.status` is NOT NULL with default "received"
- [ ] `voice_commands.intent` is NOT NULL with default "unknown"
- [ ] Composite index on `reminders (status, fire_at)` exists
- [ ] All existing tests pass after migration

## Work Log
- 2026-02-23: Identified by rails-reviewer and performance-oracle during code review
