---
status: pending
priority: p2
issue_id: "031"
tags: [code-review, api, agent-native, architecture]
---

# Text API Returns Binary Audio — No Structured Response for Agent Confirmation

## Problem Statement

`POST /api/v1/text_commands` returns a raw `audio/mpeg` binary response regardless of whether the command succeeded or failed. An agent calling this endpoint:
1. Cannot distinguish a successful reminder creation from an unrecognized command — both return `200 audio/mpeg`
2. Cannot extract the `fire_at`, message, reminder ID, or intent from the response
3. Has no machine-readable signal if the command was malformed

This is an action parity gap: a human hears the audio and can discern meaning from the words; an agent receives bytes it cannot reason over.

## Findings

- `app/controllers/api/v1/text_commands_controller.rb` line 10: `send_data audio_bytes, type: "audio/mpeg"` — always 200
- When intent is `:unknown`, `CommandResponder` returns audio saying "Sorry, I didn't understand that" — still a 200 to the agent
- Agent-native reviewer: "The agent has no way to distinguish success from failure without decoding audio"
- Relevant prior todo: `027-complete-p3-agent-native-access-gaps.md`

## Proposed Solutions

### Option A: Return JSON alongside or instead of audio (Recommended)

Return a structured JSON response with the reminder details:

```ruby
# Api::V1::TextCommandsController#create
def create
  command = CommandParser.new.parse(params[:text])
  audio   = @responder.respond(command: command, user: current_user)

  render json: {
    intent:     command[:intent],
    reminder:   current_user.reminders.last.as_json(only: [:id, :message, :fire_at, :kind]),
    audio_url:  nil   # or cache token if audio is served separately
  }, status: (command[:intent] == :unknown ? :unprocessable_entity : :created)
end
```

An agent that wants confirmation ignores audio; a human client fetches and plays the audio separately.

Effort: Medium | Risk: Medium (requires API client changes if any consumer expects raw audio bytes)

### Option B: Add JSON body to existing audio response with content-type negotiation

If current consumers depend on the raw audio response, add `Accept: application/json` negotiation:
- `Accept: audio/mpeg` → current behaviour (raw bytes)
- `Accept: application/json` → structured response with intent + reminder details

Effort: Medium | Risk: Low (backward compatible)

### Option C: Status code only (minimal)

At minimum, return `422 Unprocessable Entity` when intent is `:unknown`. This gives agents a signal without changing the response body.

Effort: Small | Risk: Low

## Acceptance Criteria

- [ ] Agent calling the text API can determine whether a reminder was created without parsing audio
- [ ] Response includes at minimum: intent, success/failure status code
- [ ] `:unknown` intent returns a non-2xx status
- [ ] Existing tests updated
- [ ] Audio playback for human voice-UI clients unaffected (if they use this endpoint)

## Work Log

- 2026-02-24: Identified by agent-native-reviewer during code review
