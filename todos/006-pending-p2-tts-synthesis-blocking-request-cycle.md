---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, performance, architecture]
---

# Move TTS Synthesis Out of the Request Cycle

## Problem Statement
`ElevenLabsClient#synthesize` is called synchronously inside `CommandResponder#respond`, which is called from `VoiceCommandsController#create`. This blocks a Puma thread for 500ms–2000ms+ of TTS inference latency on every single voice command request. With 5 default Puma threads, the app saturates at ~2–7 concurrent users.

## Findings
- `app/services/command_responder.rb` line 10: `@tts_client.synthesize(...)` called in the request cycle
- `app/controllers/voice_commands_controller.rb` line 22: `CommandResponder.new.respond(...)` called synchronously
- ElevenLabs `eleven_multilingual_v2` is a generative inference call — non-deterministic latency
- `ReminderJob` already demonstrates the correct async pattern: write audio to cache, broadcast token via Turbo Streams, client fetches from `/voice_alerts/:token`
- At 10x users: requests queue and time out before getting a response

## Proposed Solutions

### Option A: Background job for TTS (Recommended)
1. `VoiceCommandsController#create` parses transcript, saves `VoiceCommand`, enqueues a `VoiceResponseJob` and returns a Turbo Stream frame with a loading state immediately
2. `VoiceResponseJob` calls `CommandResponder` (or just `ElevenLabsClient` directly), writes audio to cache, broadcasts token via Turbo Streams
3. Client's `voice_alert_controller.js` handles the incoming stream and plays audio
- Effort: Large | Risk: Medium (requires Turbo Streams refactor on frontend)

### Option B: Stream the TTS response
Use ElevenLabs streaming API to begin sending audio bytes before synthesis is complete, reducing perceived latency without full async.
- Effort: Large | Risk: High (requires streaming HTTP client changes)

## Acceptance Criteria
- [ ] `VoiceCommandsController#create` returns a response in < 1 second (before TTS completes)
- [ ] TTS audio delivered to client asynchronously via Turbo Streams
- [ ] Puma thread not held during ElevenLabs synthesis
- [ ] All existing intent behaviors (timer, reminder, time, sunset, unknown) still work

## Work Log
- 2026-02-23: Identified by performance-oracle and architecture-strategist during code review
