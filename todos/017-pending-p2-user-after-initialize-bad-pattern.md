---
status: pending
priority: p2
issue_id: "017"
tags: [code-review, rails, performance]
---

# Replace User after_initialize with before_validation on: :create

## Problem Statement
`User#after_initialize` fires on every `User.find`, `User.new`, and eager-loaded user — not just on creation. For a `current_user` lookup on every authenticated request, this callback runs unconditionally and sets attributes on already-loaded records. The idiomatic Rails pattern for creation-only defaults is `before_validation on: :create` or database-level defaults.

## Findings
- `app/models/user.rb` lines 4–7: `after_initialize` sets `elevenlabs_voice_id` and `timezone`
- `||=` guard prevents overwriting persisted values, but the callback still runs and checks on every load
- Database schema already has `default` values for these columns (they should be set at DB level)

## Proposed Solutions

### Option A: Use before_validation on: :create (Recommended)
```ruby
before_validation :set_defaults, on: :create

private

def set_defaults
  self.elevenlabs_voice_id ||= ENV["ELEVENLABS_VOICE_ID"]
  self.timezone ||= "Eastern Time (US & Canada)"
end
```
- Effort: Small | Risk: None

### Option B: Database-level defaults via migration
Add `default:` to the schema columns and remove the callback entirely.
- Effort: Small | Risk: None | Cleanest

## Acceptance Criteria
- [ ] Default assignment no longer fires on `User.find`
- [ ] New users still get default timezone and voice_id
- [ ] Existing user spec behavior unchanged

## Work Log
- 2026-02-23: Identified by rails-reviewer, performance-oracle, simplicity-reviewer during code review
