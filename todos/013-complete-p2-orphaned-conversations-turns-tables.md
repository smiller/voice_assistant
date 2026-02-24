---
status: pending
priority: p2
issue_id: "013"
tags: [code-review, schema, cleanup]
---

# Remove Orphaned conversations and turns Tables

## Problem Statement
`db/schema.rb` defines `conversations` and `turns` tables with no corresponding models, controllers, routes, or specs anywhere in the codebase. These are dead schema artifacts that add confusion and migration surface area.

## Findings
- `db/schema.rb` lines 45–73: fully defined `conversations` and `turns` tables
- No `app/models/conversation.rb` or `app/models/turn.rb`
- No controller, route, view, or spec for either
- `turns` has `user_transcript` and `assistant_response_text` columns — likely scaffolding for an unimplemented conversational context feature

## Proposed Solutions

### Option A: Drop tables via migration (Recommended)
```ruby
def change
  drop_table :turns
  drop_table :conversations
end
```
- Effort: Small | Risk: None (no code references them)

### Option B: Implement the feature
If multi-turn conversational context is planned, wire up the models and controllers.
- Effort: Large | Risk: N/A

## Acceptance Criteria
- [ ] `conversations` and `turns` tables removed from schema
- [ ] Migration is reversible
- [ ] No references to these tables remain in any code file

## Work Log
- 2026-02-23: Identified by rails-reviewer, architecture-strategist, agent-native-reviewer during code review
