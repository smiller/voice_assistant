---
status: pending
priority: p3
issue_id: "052"
tags: [code-review, rails, looping-reminders, ui, quality]
dependencies: []
---

# Minor View and Code Quality Issues in Looping Reminders

## Problem Statement

Four small issues identified during review: inconsistent empty-state pattern in the
view, inline `? "min" : "mins"` instead of `pluralize`, `p` local variable shadowing
`Kernel#p`, and regex re-parsing in `handle_alias_loop` that should be pushed upstream
to `CommandParser`.

## Findings

### 1. Empty state pattern inconsistent

`app/views/voice_commands/index.html.erb` — looping reminders section uses a Ruby
`if/else` for the empty state, while every other list uses a static `<li class="empty-state">`
that's hidden by CSS when items exist. The current pattern prevents the empty-state `<li>`
from co-existing with a Turbo-appended item:

```erb
<% if @looping_reminders.empty? %>
  <li>No looping reminders</li>
<% else %>
  <%= render @looping_reminders %>
<% end %>
```

Should follow the pattern used for timers, reminders, and daily_reminders:
```erb
<%= render @looping_reminders %>
<li class="empty-state">No looping reminders</li>
```

### 2. Inline pluralize instead of helper

`app/views/looping_reminders/_looping_reminder.html.erb`:
```erb
<%= looping_reminder.interval_minutes == 1 ? "min" : "mins" %>
```
Should use: `<%= "min".pluralize(looping_reminder.interval_minutes) %>`

### 3. `p` local variable shadows `Kernel#p`

`app/services/command_responder.rb` line 187:
```ruby
def handle_complete_pending(params, user)
  p = params.with_indifferent_access
```
`p` is a Ruby built-in debug method. Rename to `opts` or `iparams`.

### 4. Regex re-parsing in `handle_alias_loop`

`app/services/command_responder.rb`:
```ruby
number = params[:source].match(/\brun\s+(?:loop|looping\s+reminder)\s+(\d+)/i)&.then { |m| m[1].to_i }
```

`CommandParser` already extracted the source string; the number should be extracted at
parse time and included in `alias_loop` params as `number:`. The responder shouldn't
contain regex logic.

## Proposed Solutions

All four are trivial fixes:

1. Replace the looping reminders empty state with the `<li class="empty-state">` pattern
2. Replace inline ternary with `"min".pluralize(looping_reminder.interval_minutes)`
3. Rename `p` to `opts` in `handle_complete_pending`
4. Extract number from source in `CommandParser#parse` and include as `params[:number]`
   in the `:alias_loop` command hash

## Technical Details

- `app/views/voice_commands/index.html.erb` (#1)
- `app/views/looping_reminders/_looping_reminder.html.erb` (#2)
- `app/services/command_responder.rb` (#3, #4)
- `app/services/command_parser.rb` (#4)
- `spec/services/command_parser_spec.rb` (#4 — add `number:` to alias_loop params)

## Acceptance Criteria

- [ ] Empty state for looping reminders uses `<li class="empty-state">` pattern
- [ ] Partial uses `pluralize` helper for "min/mins"
- [ ] `p` renamed to `opts` (or similar) in `handle_complete_pending`
- [ ] `alias_loop` params include `number:` from CommandParser; `handle_alias_loop`
  uses `params[:number]` directly
- [ ] All specs pass; RuboCop clean

## Work Log

- 2026-02-25: Identified by kieran-rails-reviewer and code-simplicity-reviewer during
  code review of feat/looping-reminders
