---
status: pending
priority: p3
issue_id: "051"
tags: [code-review, security, looping-reminders, validation]
dependencies: []
---

# No Length/Range Validators on `message`, `stop_phrase`, `interval_minutes`

## Problem Statement

`LoopingReminder` has no upper-bound constraints on `message`, `stop_phrase`, or
`interval_minutes`. An unbounded `message` passed to ElevenLabs inflates per-character
API costs and could exhaust quota. An extreme `interval_minutes` produces an effectively
invisible reminder (e.g., once a year). A very long `stop_phrase` makes the substring
match in `match_stop_phrase` more expensive.

## Findings

`app/models/looping_reminder.rb`:
```ruby
validates :interval_minutes, numericality: { greater_than_or_equal_to: 1 }
validates :message, presence: true
validates :stop_phrase, presence: true
```

No maximum on any of these. ElevenLabs charges per character synthesized.

`stop_phrase` has an implicit 255-char DB cap (it's a `string` column), but this is
not communicated to the model.

## Proposed Solutions

### Option A: Add length and range validators (Recommended)

```ruby
validates :message,     presence: true, length: { maximum: 500 }
validates :stop_phrase, presence: true, length: { maximum: 100 }
validates :interval_minutes, numericality: {
  greater_than_or_equal_to: 1,
  less_than_or_equal_to: 1440  # max 24 hours
}
```

**Pros:** Prevents cost amplification; sensible UX bounds; easy to adjust later
**Effort:** Trivial
**Risk:** None (no existing records violate these bounds)

## Recommended Action

Option A.

## Technical Details

- `app/models/looping_reminder.rb`
- `spec/models/looping_reminder_spec.rb` — add boundary tests

## Acceptance Criteria

- [ ] `message` has `length: { maximum: 500 }` (or similar)
- [ ] `stop_phrase` has `length: { maximum: 100 }`
- [ ] `interval_minutes` has `less_than_or_equal_to: 1440`
- [ ] Spec verifies boundary values reject/accept correctly
- [ ] Mutant passes on `LoopingReminder` validations

## Work Log

- 2026-02-25: Identified by security-sentinel during code review of feat/looping-reminders
