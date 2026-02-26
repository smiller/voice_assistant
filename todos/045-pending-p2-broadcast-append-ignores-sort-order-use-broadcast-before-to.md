---
status: pending
priority: p2
issue_id: "045"
tags: [code-review, ui, looping-reminders, turbo, known-pattern]
dependencies: []
---

# `broadcast_loop_append` Ignores Sort Order — Use `broadcast_before_to` Pattern

## Problem Statement

`CommandResponder#broadcast_loop_append` always appends the new looping reminder to the
end of the `#looping_reminders` list, ignoring `order(:number)`. When a new loop with
a lower number is created while higher-numbered loops already exist, it appears at the
end of the list instead of in its sorted position. The view controller sorts by `number`
on page load, but real-time broadcasts bypass that sort.

## Findings

**Known institutional pattern** — see:
`docs/solutions/ui-bugs/turbo-streams-ordered-insertion-broadcast-before-to.md`

The project already documented this exact problem for reminders and the fix using
`broadcast_before_to` with the next sibling's DOM ID.

`app/services/command_responder.rb`:
```ruby
def broadcast_loop_append(loop)
  Turbo::StreamsChannel.broadcast_append_to(
    loop.user,
    target: "looping_reminders",
    partial: "looping_reminders/looping_reminder",
    locals: { looping_reminder: loop }
  )
end
```

`VoiceCommandsController#index` orders by `number`:
```ruby
@looping_reminders = current_user.looping_reminders.order(:number)
```

Page load is correct. Real-time append is wrong.

## Proposed Solutions

### Option A: Use `broadcast_before_to` with next-sibling lookup (Recommended)

Following the documented solution pattern:

```ruby
def broadcast_loop_append(reminder)
  next_reminder = reminder.user.looping_reminders
                           .where("number > ?", reminder.number)
                           .order(:number).first

  if next_reminder
    Turbo::StreamsChannel.broadcast_before_to(
      reminder.user,
      target: ActionView::RecordIdentifier.dom_id(next_reminder),
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: reminder }
    )
  else
    Turbo::StreamsChannel.broadcast_append_to(
      reminder.user,
      target: "looping_reminders",
      partial: "looping_reminders/looping_reminder",
      locals: { looping_reminder: reminder }
    )
  end
end
```

**Pros:** Consistent with documented project pattern; list stays sorted after real-time
updates
**Effort:** Small
**Risk:** Low

### Option B: Re-render the entire list on every append

Always `broadcast_replace_to` the entire `#looping_reminders` list.
**Cons:** More data sent over the wire; no animation for individual items
**Risk:** Low

## Recommended Action

Option A — follows the existing project pattern exactly.

## Technical Details

- `app/services/command_responder.rb` — `broadcast_loop_append`
- `spec/services/command_responder_spec.rb` — add test for sorted insertion

See: `docs/solutions/ui-bugs/turbo-streams-ordered-insertion-broadcast-before-to.md`

## Acceptance Criteria

- [ ] `broadcast_loop_append` uses `broadcast_before_to` when a higher-numbered
  sibling exists, `broadcast_append_to` when the new loop is last
- [ ] Spec: creating a lower-numbered loop broadcasts before the higher-numbered sibling
- [ ] Spec: creating a loop with the highest number still uses `broadcast_append_to`
- [ ] Mutant passes on `broadcast_loop_append`

## Work Log

- 2026-02-25: Identified by learnings-researcher (Known Pattern from docs/solutions/)
  during code review of feat/looping-reminders
