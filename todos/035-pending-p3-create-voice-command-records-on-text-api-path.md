---
status: pending
priority: p3
issue_id: "035"
tags: [code-review, agent-native, audit, architecture]
---

# Create VoiceCommand Records on the Text API Path (Audit Parity)

## Problem Statement

`VoiceCommandsController#create` (the browser voice path) creates a `VoiceCommand` record with transcript, intent, params, and status on every command. `Api::V1::TextCommandsController#create` (the agent/text path) does not. If `VoiceCommand` records are used for history, audit, or future context injection into the agent's system prompt, all agent-originated commands are invisible in that log.

## Findings

- `app/controllers/voice_commands_controller.rb`: creates `VoiceCommand` record after parsing
- `app/controllers/api/v1/text_commands_controller.rb`: no `VoiceCommand` record created
- Agent-native reviewer: "If the record is meant to log all commands regardless of input modality, `TextCommandsController` should create one. If it is intentionally voice-only, rename it `VoiceCommand` and document that the API path is intentionally unlogged."
- Related: todo `027-complete-p3-agent-native-access-gaps.md`

## Proposed Solutions

### Option A: Create a VoiceCommand record on the text API path (Recommended)

Add the same record creation logic to `TextCommandsController#create`, passing `source: :text_api` or similar to distinguish origin.

Effort: Small | Risk: Low

### Option B: Rename model to clarify intent

If the text API path should intentionally be unlogged, rename `VoiceCommand` to something that makes the exclusion obvious (e.g. `VoiceTranscriptCommand`) and document the decision.

Effort: Medium | Risk: Medium (migration + rename)

### Option C: Document the intentional gap

Add a comment to `TextCommandsController` explaining why `VoiceCommand` is not created.

Effort: Trivial | Risk: None

## Acceptance Criteria

- [ ] Either: text API path creates a command record, OR the reason for not doing so is documented
- [ ] If records are created, they are distinguishable from voice-originated commands

## Work Log

- 2026-02-24: Identified by agent-native-reviewer during code review (finding #4)
