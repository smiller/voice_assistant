---
status: pending
priority: p2
issue_id: "016"
tags: [code-review, security, reliability]
---

# Validate Audio Upload Size and MIME Type

## Problem Statement
`VoiceCommandsController#create` calls `audio.read` with no size limit before forwarding to Deepgram. An authenticated attacker can upload arbitrarily large files, exhausting server memory. No MIME type validation exists — any file type is accepted and forwarded with hardcoded `Content-Type: audio/webm`.

## Findings
- `app/controllers/voice_commands_controller.rb` line 11: `audio.read` — no size guard
- No `params[:audio].content_type` check
- Puma's default 1MB multipart limit provides partial protection but is not explicitly set

## Proposed Solutions

### Option A: Add size and MIME guard (Recommended)
```ruby
def create
  audio = params[:audio]
  return head :bad_request unless audio
  return head :unprocessable_entity if audio.size > 1.megabyte
  return head :unprocessable_entity unless audio.content_type&.start_with?("audio/")
  ...
end
```
- Effort: Small | Risk: None

## Acceptance Criteria
- [ ] Uploads > 1MB rejected with 422
- [ ] Non-audio MIME types rejected with 422
- [ ] Valid WebM audio still processed correctly

## Work Log
- 2026-02-23: Identified by security-sentinel during code review
