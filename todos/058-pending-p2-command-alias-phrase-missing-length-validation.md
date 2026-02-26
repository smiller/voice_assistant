---
status: pending
priority: p2
issue_id: "058"
tags: [code-review, security, looping-reminders, validation]
dependencies: []
---

# `CommandAlias#phrase` Missing Length Validation

## Problem Statement

Todo 051 added length validators to `LoopingReminder` (message ≤ 500, stop_phrase ≤ 100) but `CommandAlias#phrase` has no upper-bound length constraint. An alias phrase is passed to `User#phrase_taken?` which does a DB LOWER() comparison and to ElevenLabs synthesis indirectly (the alias is echoed back in the confirmation TTS). An unbounded phrase can inflate TTS costs and make the substring match in `match_stop_phrase`-like operations more expensive.

## Findings

- `app/models/command_alias.rb:5-7` — only `presence:` and `uniqueness:` validation; no `length:` constraint.
- `db/schema.rb` — `phrase` is a `string` column (implicit 255-char DB cap) but this is not communicated to the model layer.
- `app/services/command_responder.rb:217` — alias phrase is echoed in TTS: `"Alias '#{phrase}' created for looping reminder #{looping_reminder.number}"`.
- Identified by security-sentinel (P2).

## Proposed Solutions

### Option A: Add `length` validator to `CommandAlias` (Recommended)

```ruby
validates :phrase, presence: true,
                   length: { maximum: 100 },
                   uniqueness: { scope: :user_id, case_sensitive: false }
```

100 characters matches the `stop_phrase` limit and is a natural alias phrase bound.

**Pros:** Trivial; consistent with sibling validators; explicitly communicates DB constraint.
**Cons:** None.

**Effort:** 15 minutes
**Risk:** None

## Recommended Action

Option A. One-liner.

## Technical Details

**Affected files:**
- `app/models/command_alias.rb`
- `spec/models/command_alias_spec.rb` — add boundary test

## Acceptance Criteria

- [ ] `phrase` validates `length: { maximum: 100 }`
- [ ] Spec verifies 100-char phrase accepted, 101-char rejected
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by security-sentinel during final PR review.
