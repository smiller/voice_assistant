---
status: complete
priority: p2
issue_id: "043"
tags: [code-review, rails, looping-reminders, dry, quality]
dependencies: []
---

# `phrase_taken?` Duplicated in Two Services — Move to User Model

## Problem Statement

`CommandResponder#phrase_taken_for_user?` and `LoopingReminderDispatcher#phrase_taken?`
are byte-for-byte identical. Any future change to phrase-collision rules (e.g., adding a
third phrase-bearing table) must be made in both places and both must stay synchronized.
They're misnamed — same logic, different method names.

## Findings

`app/services/command_responder.rb` lines 233-236:
```ruby
def phrase_taken_for_user?(phrase, user)
  user.looping_reminders.where("LOWER(stop_phrase) = ?", phrase.downcase).exists? ||
    user.command_aliases.where("LOWER(phrase) = ?", phrase.downcase).exists?
end
```

`app/services/looping_reminder_dispatcher.rb` lines 55-58:
```ruby
def phrase_taken?(phrase, user)
  user.looping_reminders.where("LOWER(stop_phrase) = ?", phrase.downcase).exists? ||
    user.command_aliases.where("LOWER(phrase) = ?", phrase.downcase).exists?
end
```

## Proposed Solutions

### Option A: Move to `User#phrase_taken?(phrase)` (Recommended)

The query is a domain question about a user's phrase namespace. `User` already owns both
associations (`has_many :looping_reminders`, `has_many :command_aliases`):

```ruby
# app/models/user.rb
def phrase_taken?(phrase)
  looping_reminders.where("LOWER(stop_phrase) = ?", phrase.downcase).exists? ||
    command_aliases.where("LOWER(phrase) = ?", phrase.downcase).exists?
end
```

Call sites become `user.phrase_taken?(phrase)` — reads as a natural domain question.

**Pros:** Single authoritative location; testable independently in `user_spec.rb`;
one place to update when schema evolves
**Effort:** Small
**Risk:** Low

### Option B: Extract to a shared module/concern

Create `PhraseTakenChecker` module included in both services.
**Cons:** Adds indirection for no gain — both services already receive the user as arg;
a module is the wrong tool when a model method suffices
**Risk:** Low

## Recommended Action

Option A.

## Technical Details

- `app/models/user.rb`
- `app/services/command_responder.rb` (remove `phrase_taken_for_user?`, update callers)
- `app/services/looping_reminder_dispatcher.rb` (remove `phrase_taken?`, update callers)
- `spec/models/user_spec.rb` (add `phrase_taken?` tests)
- `spec/services/command_responder_spec.rb` (callers still work)
- `spec/services/looping_reminder_dispatcher_spec.rb` (callers still work)

## Acceptance Criteria

- [ ] `User#phrase_taken?(phrase)` added to `user.rb`
- [ ] `phrase_taken_for_user?` removed from `CommandResponder`
- [ ] `phrase_taken?` removed from `LoopingReminderDispatcher`
- [ ] All callers updated to `user.phrase_taken?`
- [ ] `user_spec.rb` covers: stop_phrase collision, alias collision, no collision,
  case-insensitive matching on both sides
- [ ] Mutant passes on `User#phrase_taken?`

## Work Log

- 2026-02-25: Identified by kieran-rails-reviewer, architecture-strategist, and
  code-simplicity-reviewer during code review of feat/looping-reminders
