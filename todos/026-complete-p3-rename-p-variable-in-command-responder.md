---
status: pending
priority: p3
issue_id: "026"
tags: [code-review, quality, rails]
dependencies: []
---

# Rename `p` Variable in `CommandResponder` (Shadows Kernel Method)

## Problem Statement

`CommandResponder#response_text` uses `p` as a local variable name for parsed reminder params. `p` is a Ruby Kernel method (`Kernel#p`) used for debug printing. Shadowing it with a local variable is misleading, can confuse newer developers, and triggers RuboCop's `Lint/ShadowingOuterLocalVariable` cop.

## Findings

In `app/services/command_responder.rb:28`:

```ruby
when :reminder
  p = command[:params]   # shadows Kernel#p
  time_str = format_time(p[:hour], p[:minute])
  ...
when :daily_reminder
  p = command[:params]   # shadows Kernel#p again
```

## Proposed Solutions

### Option A: Rename to `params` (Recommended)

```ruby
when :reminder
  params = command[:params]
  time_str = format_time(params[:hour], params[:minute])
  tomorrow = resolve_reminder_time(params, user).to_date > ...
  "Reminder set for #{time_str}#{' tomorrow' if tomorrow} to #{params[:message]}"
```

**Pros:** Descriptive, idiomatic, no shadowing
**Cons:** None
**Effort:** Trivial
**Risk:** None

### Option B: Inline `command[:params]`

Avoid the local variable entirely and reference `command[:params][:hour]` directly. Works when used only once per key, but becomes verbose with multiple accesses.

## Acceptance Criteria

- [ ] No variable named `p` in `CommandResponder`
- [ ] RuboCop `Lint/ShadowingOuterLocalVariable` passes
- [ ] Existing specs pass unchanged

## Work Log

- 2026-02-23: Identified during code review
