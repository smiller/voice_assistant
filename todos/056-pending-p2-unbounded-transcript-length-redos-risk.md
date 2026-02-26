---
status: pending
priority: p2
issue_id: "056"
tags: [code-review, security, api, input-validation, looping-reminders]
dependencies: []
---

# Unbounded Transcript Length Enables Resource Exhaustion and ReDoS Risk

## Problem Statement

`POST /api/v1/text_commands` accepts a `transcript` parameter with only a `blank?` check. An arbitrarily long transcript is passed directly into `LoopingReminderDispatcher#dispatch` which:
1. Calls `match_stop_phrase`, iterating all active loops and calling `transcript.downcase.include?(lr.stop_phrase.downcase)` — O(n × m) where m is transcript length.
2. Calls `CommandParser#parse` whose regexes operate on the full input.

Although no current regex is catastrophically backtracking, future regex additions against unbounded input can silently become ReDoS vectors. More immediately, a transcript of 100 KB would cause measurable latency in both operations and allocate proportional Ruby strings.

## Findings

- `app/controllers/api/v1/text_commands_controller.rb:6` — only `transcript.blank?` validation; no length cap.
- `app/services/looping_reminder_dispatcher.rb:26-29` — `match_stop_phrase` iterates active loops; string ops scale with transcript.
- `app/services/command_parser.rb:90-98` — `normalize_numbers` runs `gsub` repeatedly across the whole string.
- Voice command endpoint (`VoiceCommandsController`) constrains audio to 1 MB, but the derived transcript has no constraint.
- Identified by security-sentinel (P2).

## Proposed Solutions

### Option A: Add maximum transcript length validation in controller (Recommended)

```ruby
# app/controllers/api/v1/text_commands_controller.rb
MAX_TRANSCRIPT_LENGTH = 1000

def create
  transcript = params[:transcript]
  return head :bad_request if transcript.blank?
  return head :unprocessable_entity if transcript.length > MAX_TRANSCRIPT_LENGTH
  # ...
end
```

A typical voice command is under 100 characters; 1 000 characters is generous and defensible.

**Pros:** Minimal change; co-located with existing validation; easy to tune.
**Cons:** Magic number in controller — consider extracting to a constant or config.

**Effort:** 30 minutes
**Risk:** Low

---

### Option B: Validate at the `VoiceCommand` model level

Add a `validates :transcript, length: { maximum: 1000 }` to `VoiceCommand`.

**Pros:** Validation in the model, survives alternate paths.
**Cons:** Validation error raised after some processing already happened.

**Effort:** 30 minutes
**Risk:** Low

---

### Option C: Truncate at transcription boundary

Cap transcript at transcription time in `DeepgramClient` or in the voice command controller after transcription.

**Pros:** Covers the voice path.
**Cons:** Text API path still unbounded without separate validation.

**Effort:** 1 hour
**Risk:** Low

## Recommended Action

Option A in the text commands controller, plus Option B in the model for defence-in-depth.

## Technical Details

**Affected files:**
- `app/controllers/api/v1/text_commands_controller.rb`
- `app/models/voice_command.rb` (if model-level validation added)
- `spec/controllers/api/v1/text_commands_controller_spec.rb`

## Acceptance Criteria

- [ ] Text command endpoint rejects transcripts longer than 1000 characters with 422
- [ ] Spec verifies boundary (1000 chars accepted, 1001 rejected)
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by security-sentinel during final PR review.
