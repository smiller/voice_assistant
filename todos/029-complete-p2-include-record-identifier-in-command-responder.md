---
status: pending
priority: p2
issue_id: "029"
tags: [code-review, rails, architecture, maintenance]
---

# Include ActionView::RecordIdentifier in CommandResponder

## Problem Statement

`CommandResponder#schedule_reminder` calls `ActionView::RecordIdentifier.dom_id(next_reminder)` via explicit module reference, while `ReminderJob#perform` calls `dom_id(next_sibling)` directly because it already includes `ActionView::RecordIdentifier`. Both produce identical strings today, but the two sites generate DOM IDs using inconsistent mechanisms. If a custom prefix is ever needed, or if `ActionView::RecordIdentifier` changes its implementation, only one site will drift.

## Findings

- `app/services/command_responder.rb` line 64: `ActionView::RecordIdentifier.dom_id(next_reminder)` — explicit module call
- `app/jobs/reminder_job.rb` line 36: `dom_id(next_sibling)` — via included module
- The PR notes "CommandResponder does NOT include ActionView::RecordIdentifier, hence the explicit module reference" — but this is easily fixed with one line
- Rails reviewer: "Including the module is trivial — `include ActionView::RecordIdentifier` — and eliminates the inconsistency"

## Proposed Solutions

### Option A: Include the module (Recommended)

```ruby
class CommandResponder
  include ActionView::RecordIdentifier

  def initialize(...)
  ...

  # then use dom_id directly:
  target: dom_id(next_reminder),
```

Effort: Small | Risk: None (purely cosmetic change, same output)

### Option B: Keep explicit module reference but document it

Add a comment: `# Explicit because CommandResponder is a PORO — dom_id not available without including ActionView::RecordIdentifier`

This leaves the inconsistency in place but makes the reason legible.

Effort: Trivial | Risk: None

## Acceptance Criteria

- [ ] Both `CommandResponder` and `ReminderJob` call `dom_id` via the same mechanism
- [ ] All existing tests pass unchanged
- [ ] RuboCop clean

## Work Log

- 2026-02-24: Identified by kieran-rails-reviewer during code review (finding #3)
