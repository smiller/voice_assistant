---
status: pending
priority: p2
issue_id: "046"
tags: [code-review, performance, looping-reminders, database, views]
dependencies: []
---

# `command_aliases` Queried Twice in Partial — Missing `includes` in Controller and Responder

## Problem Statement

`_looping_reminder.html.erb` calls `command_aliases.any?` then `command_aliases.map`,
firing two queries per partial render. The controller doesn't preload `command_aliases`,
so the partial fires 2n queries for n looping reminders on page load. The same issue
occurs when `CommandResponder` passes a LoopingReminder to `broadcast_replace_to` without
preloading aliases.

## Findings

`app/views/looping_reminders/_looping_reminder.html.erb`:
```erb
<% if looping_reminder.command_aliases.any? %>
  (<%= looping_reminder.command_aliases.map(&:phrase).join(", ") %>)
<% end %>
```

Two queries: `SELECT 1 FROM command_aliases WHERE ... LIMIT 1` + `SELECT * FROM command_aliases WHERE ...`.

`app/controllers/voice_commands_controller.rb`:
```ruby
@looping_reminders = current_user.looping_reminders.order(:number)
```

No `includes(:command_aliases)`.

`CommandResponder#handle_run_loop`, `handle_stop_loop`, `handle_alias_loop`,
`handle_complete_pending` all call `broadcast_replace_to` with a `looping_reminder`
object that has no preloaded `command_aliases`.

## Proposed Solutions

### Option A: Add `includes` in controller + simplify partial (Recommended)

```ruby
# app/controllers/voice_commands_controller.rb
@looping_reminders = current_user.looping_reminders.includes(:command_aliases).order(:number)
```

Simplify the partial to one collection traversal:
```erb
<% aliases = looping_reminder.command_aliases.map(&:phrase).join(", ") %>
<% if aliases.present? %>(<%= aliases %>)<% end %>
```

For broadcast contexts, reload with associations before passing to broadcast:
```ruby
# In CommandResponder, before broadcast_replace_to:
reminder = user.looping_reminders.includes(:command_aliases).find(reminder.id)
```

**Pros:** Eliminates 2n queries on page load; consistent rendering in broadcasts
**Effort:** Small
**Risk:** None

### Option B: Collapse partial to `join` + `presence`

```erb
<%= "(#{looping_reminder.command_aliases.map(&:phrase).join(", ")})".presence %>
```

This still fires two queries without the controller change, but collapses the Ruby logic.

## Recommended Action

Option A — fix the root cause (missing includes) and simplify the partial.

## Technical Details

- `app/controllers/voice_commands_controller.rb` — add `includes(:command_aliases)`
- `app/views/looping_reminders/_looping_reminder.html.erb` — collapse to one traversal
- `app/services/command_responder.rb` — reload with includes before broadcast

## Acceptance Criteria

- [ ] Controller loads `includes(:command_aliases)` with `@looping_reminders`
- [ ] Partial uses a single `command_aliases` traversal (not `.any?` + `.map`)
- [ ] Broadcasts pass a LoopingReminder with preloaded `command_aliases`
- [ ] Page load triggers exactly 2 queries for n looping reminders (associations + main)

## Work Log

- 2026-02-25: Identified by performance-oracle and code-simplicity-reviewer during
  code review of feat/looping-reminders
