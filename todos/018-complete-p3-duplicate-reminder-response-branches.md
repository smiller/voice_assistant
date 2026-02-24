---
status: pending
priority: p3
issue_id: "018"
tags: [code-review, quality, rails]
dependencies: []
---

# Duplicate `:reminder` / `:daily_reminder` Response Branches in CommandResponder

## Problem Statement

`CommandResponder#response_text` contains two nearly identical `when` branches for `:reminder` and `:daily_reminder`. The only difference is the leading word ("Reminder" vs "Daily reminder") and the prefix word stored in the response string. This violates DRY and means any future change to reminder formatting must be made in two places.

## Findings

In `app/services/command_responder.rb:28-36`:

```ruby
when :reminder
  p = command[:params]
  time_str = format_time(p[:hour], p[:minute])
  tomorrow = resolve_reminder_time(p, user).to_date > Time.current.in_time_zone(user.timezone).to_date
  "Reminder set for #{time_str}#{' tomorrow' if tomorrow} to #{p[:message]}"
when :daily_reminder
  p = command[:params]
  time_str = format_time(p[:hour], p[:minute])
  tomorrow = resolve_reminder_time(p, user).to_date > Time.current.in_time_zone(user.timezone).to_date
  "Daily reminder set for #{time_str}#{' tomorrow' if tomorrow} to #{p[:message]}"
```

Four of the five lines are identical.

## Proposed Solutions

### Option A: Extract shared helper (Recommended)

Extract a private `reminder_response_text` method that accepts a `prefix` argument:

```ruby
when :reminder
  reminder_response_text(command[:params], user, prefix: "Reminder")
when :daily_reminder
  reminder_response_text(command[:params], user, prefix: "Daily reminder")

def reminder_response_text(params, user, prefix:)
  time_str = format_time(params[:hour], params[:minute])
  tomorrow = resolve_reminder_time(params, user).to_date > Time.current.in_time_zone(user.timezone).to_date
  "#{prefix} set for #{time_str}#{' tomorrow' if tomorrow} to #{params[:message]}"
end
```

**Pros:** Clean, testable, eliminates duplication
**Cons:** Minor restructure
**Effort:** Small
**Risk:** Low

### Option B: Use intent to derive prefix inline

```ruby
when :reminder, :daily_reminder
  prefix = command[:intent] == :daily_reminder ? "Daily reminder" : "Reminder"
  p = command[:params]
  time_str = format_time(p[:hour], p[:minute])
  tomorrow = resolve_reminder_time(p, user).to_date > Time.current.in_time_zone(user.timezone).to_date
  "#{prefix} set for #{time_str}#{' tomorrow' if tomorrow} to #{p[:message]}"
```

**Pros:** Fewer methods, same file
**Cons:** Slightly less readable
**Effort:** Small
**Risk:** Low

## Acceptance Criteria

- [ ] Duplicate lines are removed
- [ ] Existing CommandResponder specs pass unchanged
- [ ] RuboCop clean

## Work Log

- 2026-02-23: Identified during code review
