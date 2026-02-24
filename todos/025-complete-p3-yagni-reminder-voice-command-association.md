---
status: pending
priority: p3
issue_id: "025"
tags: [code-review, quality, rails]
dependencies: []
---

# YAGNI: `Reminder#voice_command` Association Never Populated

## Problem Statement

`Reminder` has a `belongs_to :voice_command, optional: true` (or a `voice_command_id` foreign key column) that is never assigned anywhere in the codebase. `CommandResponder#schedule_reminder` creates reminders without setting `voice_command_id`. The association exists speculatively, adds a nullable FK column to the schema, and misleads readers into thinking reminders are linked to voice commands.

## Findings

- `Reminder` model defines the association
- `db/schema.rb` includes `voice_command_id` column on `reminders`
- No write of `voice_command_id` in `CommandResponder`, `ReminderJob`, or any controller
- No read of `reminder.voice_command` anywhere

The association was added "just in case" but has never been used.

## Proposed Solutions

### Option A: Remove the association and column via migration (Recommended)

```ruby
# Migration
remove_column :reminders, :voice_command_id, :bigint
```

```ruby
# Model — remove
belongs_to :voice_command, optional: true
```

**Pros:** Cleaner schema, no nullable FK sitting unused, no misleading association
**Cons:** Requires migration
**Effort:** Small
**Risk:** Low — verify no data in the column before dropping

### Option B: Keep but add a TODO comment

```ruby
# TODO: populate when voice command tracking is added
belongs_to :voice_command, optional: true
```

**Pros:** Zero risk
**Cons:** YAGNI violation persists
**Effort:** Trivial
**Risk:** None

## Acceptance Criteria

- [ ] `voice_command_id` column confirmed empty in production before removal
- [ ] Migration removes the column
- [ ] Association removed from `Reminder` model
- [ ] Factory updated
- [ ] Specs and RuboCop clean

## Work Log

- 2026-02-23: Identified during code review
