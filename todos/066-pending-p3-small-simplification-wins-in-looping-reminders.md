---
status: pending
priority: p3
issue_id: "066"
tags: [code-review, quality, looping-reminders, simplification]
dependencies: []
---

# Small Simplification Wins Across Looping Reminders Code

## Problem Statement

Four minor redundancies identified by code-simplicity-reviewer that can each be fixed in under 5 minutes:

1. `LoopingReminderJob` includes `ActionView::RecordIdentifier` but never calls `dom_id`
2. `handle_alias_loop` has a redundant `&&` short-circuit guard
3. `handle_complete_pending` calls `with_indifferent_access` on a hash that is already indifferent
4. `unrecognized_command` is a private method wrapping a two-key hash literal called from one place

## Findings

**1. Unused `include ActionView::RecordIdentifier` in `LoopingReminderJob`**
- `app/jobs/looping_reminder_job.rb:2`
- The job broadcasts to a hard-coded string `"voice_alerts"`, never calls `dom_id`. The include was copied from `CommandResponder`.

**2. Redundant `&&` in `handle_alias_loop` (`command_responder.rb:167`)**
```ruby
reminder = params[:number] && user.looping_reminders.find_by(number: params[:number])
```
`find_by(number: nil)` returns `nil` regardless, making the short-circuit redundant. Simpler:
```ruby
reminder = user.looping_reminders.find_by(number: params[:number])
```

**3. Redundant `with_indifferent_access` in `handle_complete_pending` (`command_responder.rb:184`)**
```ruby
opts = params.with_indifferent_access
```
`params` arrives from `LoopingReminderDispatcher` as the result of `pending.context.with_indifferent_access.merge(...)`, which produces a `HashWithIndifferentAccess`. The second call is a no-op. Remove the local alias `opts` and use `params` directly.

**4. `unrecognized_command` private method in `CommandParser` (`command_parser.rb:61-63`)**
```ruby
def unrecognized_command
  { intent: :unknown, params: {} }
end
```
Called once, at the tail of a `||` chain. Inlining the hash literal makes the fallback nature immediately visible without a method hop.

## Proposed Solutions

### Option A: Apply all four fixes in one small PR (Recommended)

Each is a one-liner change with no behaviour impact.

**Effort:** 30 minutes total
**Risk:** None

## Recommended Action

Option A.

## Technical Details

**Affected files:**
- `app/jobs/looping_reminder_job.rb:2` — remove `include ActionView::RecordIdentifier`
- `app/services/command_responder.rb:167` — remove `params[:number] &&`
- `app/services/command_responder.rb:184` — remove `opts = params.with_indifferent_access`, use `params` directly
- `app/services/command_parser.rb:19-23, 61-63` — inline `{ intent: :unknown, params: {} }`, remove method

## Acceptance Criteria

- [ ] `LoopingReminderJob` does not include `ActionView::RecordIdentifier`
- [ ] `handle_alias_loop` uses `find_by(number: params[:number])` directly
- [ ] `handle_complete_pending` uses `params` directly (no `opts` alias, no second `with_indifferent_access`)
- [ ] `CommandParser#parse` inlines fallback hash; `unrecognized_command` method removed
- [ ] All specs pass; mutant passes; RuboCop clean

## Work Log

- 2026-02-26: Identified by code-simplicity-reviewer during final PR review.
