---
date: 2026-02-23
topic: voice-assistant
---

# Voice Assistant Rails App

## What We're Building

A multi-user, browser-based voice assistant built on Rails. Users press spacebar to record a voice command; the audio is sent to Deepgram for speech-to-text, parsed against a set of regex patterns to extract intent and parameters, and responded to with synthesized speech via ElevenLabs. Delayed commands (timers, reminders) are scheduled via Sidekiq and delivered back to the open browser tab through Turbo Streams over Action Cable.

## Core Command Types

| Command | Example | Response mechanism |
|---------|---------|-------------------|
| Immediate query | "time check", "sunset" | Synchronous — respond in the same request cycle |
| Delayed trigger | "set timer for 10 minutes", "set 7am reminder to write morning pages" | Sidekiq job fires at scheduled time → Turbo Stream pushes audio to browser |

## Architecture Flow

```
Spacebar held/toggled
  → MediaRecorder captures audio (WebM/Opus)
  → POST /voice_commands (multipart audio)
  → Deepgram STT → transcribed text
  → Regex command parser → intent + params
  → Immediate: ElevenLabs TTS → audio returned in response
  → Delayed: Sidekiq job scheduled → fires at time → ElevenLabs TTS
                                   → Action Cable Turbo Stream → browser Audio API plays
```

## Key Decisions

- **Input trigger**: Keyboard shortcut (spacebar) — explicit, no false triggers, works well on desktop browser
- **STT**: Deepgram — fast, accurate, simple REST upload
- **TTS**: ElevenLabs — high quality voice synthesis
- **Command parsing**: Regex/pattern matching to start; LLM intent parsing deferred until patterns prove insufficient
- **Delayed delivery**: Turbo Streams over Action Cable — fits the Hotwire stack, Rails-native real-time push
- **Background jobs**: Sidekiq for timer/reminder scheduling
- **Multi-user**: Commands and reminders scoped to authenticated users; Action Cable subscription scoped per user

## Resolved Decisions

- **Sunset data**: sunrise-sunset.org API
- **Closed tab**: silently drop — if no Action Cable connection exists when a job fires, discard the response
- **Reminder recurrence**: two types distinguished by command — "set 7am reminder …" (one-time), "set daily 7am reminder …" (repeating, rescheduled after each fire)
- **Per-user voice**: each user stores an ElevenLabs voice ID; used for all TTS responses for that user

## Open Questions

- None

## Next Steps

→ `/workflows:plan` for implementation details
