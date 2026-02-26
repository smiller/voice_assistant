---
status: pending
priority: p2
issue_id: "047"
tags: [code-review, rails, looping-reminders, dry, quality]
dependencies: [043]
---

# Duplicated Loop and Alias Creation Logic in `handle_complete_pending`

## Problem Statement

`handle_complete_pending` duplicates the loop-creation sequence from `handle_create_loop`
and the alias-creation sequence from `handle_alias_loop`. Two private method extractions
would eliminate the duplication and ensure future changes to creation logic (e.g.,
adding a webhook, changing the TTS confirmation text) only need to be made once.

## Findings

**Loop creation duplicated** (`handle_create_loop` lines 117-127 vs `handle_complete_pending` else branch lines 199-209):
```ruby
# Both do exactly:
loop = LoopingReminder.create!(user: user, number: LoopingReminder.next_number_for(user),
  interval_minutes: ..., message: ..., stop_phrase: ..., active: true)
schedule_loop_job(loop)
broadcast_loop_append(loop)
loop_created_text(loop)
```

**Alias creation duplicated** (`handle_alias_loop` lines 176-183 vs `handle_complete_pending` alias branch lines 190-197):
```ruby
# Both do exactly:
CommandAlias.create!(user: user, looping_reminder: loop, phrase: ...)
Turbo::StreamsChannel.broadcast_replace_to(user, target: dom_id(loop), ...)
"Alias '#{phrase}' created for looping reminder #{loop.number}"
```

## Proposed Solutions

### Option A: Extract two private methods (Recommended)

```ruby
# private
def create_looping_reminder(user:, interval_minutes:, message:, stop_phrase:)
  reminder = LoopingReminder.create!(
    user: user,
    number: LoopingReminder.next_number_for(user),
    interval_minutes: interval_minutes,
    message: message,
    stop_phrase: stop_phrase,
    active: true
  )
  schedule_loop_job(reminder)
  broadcast_loop_append(reminder)
  loop_created_text(reminder)
end

def create_command_alias(user:, looping_reminder:, phrase:)
  CommandAlias.create!(user: user, looping_reminder: looping_reminder, phrase: phrase)
  Turbo::StreamsChannel.broadcast_replace_to(
    user,
    target: dom_id(looping_reminder),
    partial: "looping_reminders/looping_reminder",
    locals: { looping_reminder: looping_reminder }
  )
  "Alias '#{phrase}' created for looping reminder #{looping_reminder.number}"
end
```

`handle_create_loop` and `handle_complete_pending` (stop_phrase path) both call
`create_looping_reminder`. `handle_alias_loop` and `handle_complete_pending` (alias path)
both call `create_command_alias`.

**Pros:** ~18 lines removed; single place to update creation logic
**Effort:** Small
**Risk:** Low

## Recommended Action

Option A. Note: resolve todo #043 (move `phrase_taken?` to User) alongside this for
maximum cleanup.

## Technical Details

- `app/services/command_responder.rb`
- `spec/services/command_responder_spec.rb` — existing tests still cover both paths

## Acceptance Criteria

- [ ] `create_looping_reminder(user:, interval_minutes:, message:, stop_phrase:)` private method exists
- [ ] `create_command_alias(user:, looping_reminder:, phrase:)` private method exists
- [ ] `handle_create_loop`, `handle_complete_pending` (stop_phrase path), `handle_alias_loop`,
  `handle_complete_pending` (alias path) all delegate to these helpers
- [ ] All existing specs pass; no duplicated logic remains

## Work Log

- 2026-02-25: Identified by code-simplicity-reviewer and kieran-rails-reviewer during
  code review of feat/looping-reminders
