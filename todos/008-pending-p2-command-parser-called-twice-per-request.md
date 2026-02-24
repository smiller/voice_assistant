---
status: pending
priority: p2
issue_id: "008"
tags: [code-review, performance, architecture]
---

# Eliminate Double CommandParser Call Per Request

## Problem Statement
`VoiceCommandsController#create` calls `CommandParser.new.parse(transcript)` on line 14 to build the `VoiceCommand` record, then passes the raw `transcript` to `CommandResponder#respond` which calls `CommandParser.new.parse(transcript)` again internally. The transcript is parsed twice per request. More critically, if the two parses somehow disagree, the stored `VoiceCommand#intent` could differ from the intent actually acted upon.

## Findings
- `app/controllers/voice_commands_controller.rb` line 14: `parsed = CommandParser.new.parse(transcript)`
- `app/services/command_responder.rb` line 7: `command = CommandParser.new.parse(transcript)` — second parse
- Redundant work + latent consistency risk
- `CommandResponder` currently accepts `transcript:` but should accept `command:` directly

## Proposed Solutions

### Option A: Pass parsed command into CommandResponder (Recommended)
Change `CommandResponder#respond` to accept `command:` (the already-parsed hash) instead of `transcript:`. The controller parses once and passes the result to both `VoiceCommand.create!` and `CommandResponder#respond`.
```ruby
# controller
parsed = CommandParser.new.parse(transcript)
VoiceCommand.create!(... intent: parsed[:intent] ...)
CommandResponder.new.respond(command: parsed, user: current_user)
```
- Effort: Medium | Risk: Low

### Option B: Have CommandResponder return the parsed command
`CommandResponder#respond` returns `[audio_bytes, parsed_command]` so the controller can use the same parse result for logging.
- Effort: Medium | Risk: Low

## Acceptance Criteria
- [ ] `CommandParser.new.parse` called exactly once per request
- [ ] `VoiceCommand#intent` always matches the intent acted upon by `CommandResponder`
- [ ] All specs pass with refactored interface

## Work Log
- 2026-02-23: Identified by rails-reviewer, performance-oracle, architecture-strategist, simplicity-reviewer
