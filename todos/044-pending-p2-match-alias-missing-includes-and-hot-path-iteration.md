---
status: pending
priority: p2
issue_id: "044"
tags: [code-review, performance, looping-reminders, database]
dependencies: []
---

# `match_alias` Missing `includes(:looping_reminder)` — N+1 on Hot Path

## Problem Statement

`LoopingReminderDispatcher#match_alias` loads all command aliases into Ruby and iterates,
then when a match is found accesses `al.looping_reminder.number` — firing a second query
(N+1 per match). This runs on every single voice command, making it the hot path.

## Findings

`app/services/looping_reminder_dispatcher.rb`:
```ruby
def match_alias(transcript, user)
  user.command_aliases.find { |al| al.phrase.casecmp?(transcript.strip) }
end
```

Line 13, caller:
```ruby
if (al = match_alias(transcript, user))
  return { intent: :run_loop, params: { number: al.looping_reminder.number } }
end
```

`al.looping_reminder` is not preloaded, so this fires a second SELECT for the matched
alias. The fix is trivially `includes(:looping_reminder)`.

Additionally, the Ruby-side `find` block can be replaced with a SQL lookup using the
existing `(user_id, phrase)` unique index on `command_aliases`, turning two queries into
one indexed lookup.

## Proposed Solutions

### Option A: Add `includes(:looping_reminder)` (Quick fix)

```ruby
def match_alias(transcript, user)
  user.command_aliases.includes(:looping_reminder)
      .find { |al| al.phrase.casecmp?(transcript.strip) }
end
```

Eliminates the N+1 with one word. Still loads all aliases into Ruby.
**Effort:** Trivial
**Risk:** None

### Option B: Push to SQL using the existing unique index (Recommended)

```ruby
def match_alias(transcript, user)
  user.command_aliases
      .includes(:looping_reminder)
      .where("LOWER(phrase) = ?", transcript.strip.downcase)
      .first
end
```

Uses the `index_command_aliases_on_user_id_and_phrase` unique index for a single-row
lookup. Returns nil (no match) or the alias with looping_reminder preloaded.
**Pros:** One indexed query instead of full table scan; scales to any number of aliases
**Effort:** Small
**Risk:** Low — same semantics, just faster

## Recommended Action

Option B — it's the same effort as A and removes the Ruby iteration entirely.

## Technical Details

- `app/services/looping_reminder_dispatcher.rb` — `match_alias`
- `spec/services/looping_reminder_dispatcher_spec.rb`

## Acceptance Criteria

- [ ] `match_alias` uses SQL WHERE for the phrase lookup (not Ruby `find`)
- [ ] `includes(:looping_reminder)` prevents the N+1 on `.number` access
- [ ] Spec passes; mutant passes on `match_alias`

## Work Log

- 2026-02-25: Identified by performance-oracle and kieran-rails-reviewer during
  code review of feat/looping-reminders
