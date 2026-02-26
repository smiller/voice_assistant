---
date: 2026-02-26
title: "Deepgram quote-stripping breaks regex parsing; TTS responses lack on-screen feedback"
tags:
  - deepgram
  - elevenlabs
  - tts
  - stt
  - regex
  - hotwire
  - stimulus
  - voice-commands
  - http-headers
modules:
  - app/services/command_parser.rb
  - app/controllers/voice_commands_controller.rb
  - app/services/command_responder.rb
  - app/javascript/controllers/voice_controller.js
problem_type: integration-issues
symptoms:
  - Voice commands containing quoted strings (alias, looping reminder) silently fell through to wrong or unknown intent because Deepgram strips single-quote punctuation from transcripts
  - ElevenLabs TTS audio played successfully but the status indicator reset to "Ready" immediately with no visible response text shown to the user
  - Blank transcripts from Deepgram previously returned HTTP 204/400 with no audio or on-screen feedback
status: solved
---

# Deepgram quote-stripping breaks regex parsing; TTS responses lack on-screen feedback

Two integration problems discovered while building the looping-reminders feature: speech-to-text punctuation normalization breaks regex delimiters, and synthesized voice responses have no corresponding on-screen display.

## Symptoms

**Regex / parse failures:**
- Saying `"alias run loop 1 as meds"` (no quotes) → intent parsed as `:run_loop` instead of `:alias_loop`
- Saying `"looping reminder every 5 minutes saying did you take your meds until I say yes I did"` → `:unknown` instead of `:create_loop`
- Symptoms only appeared in production — tests used quoted fixture strings that matched the old regex

**No on-screen response text:**
- After any voice command, the status line jumped straight to "Ready" while audio was still playing
- When Deepgram returned an empty transcript (silence, poor mic), the user saw "Error: Server error: 400" in the status area or nothing at all
- For unrecognised commands, audio played "Sorry, I didn't understand that" but the screen showed nothing

## Root Cause

**Problem 1 — Deepgram strips punctuation.**
Deepgram's pre-recorded REST API normalises transcriptions to prose: punctuation marks including single quotes, double quotes, parentheses, and commas are stripped by default. Regex patterns that required literal `'` characters as phrase delimiters never matched real transcriptions — only test fixtures that had been hand-written with quotes.

**Problem 2 — No mechanism to surface TTS text on screen.**
The controller sent raw audio bytes (`send_data`) with no accompanying text payload. The Stimulus controller had no way to know what was spoken. The previous `updateStatus("Ready")` call fired immediately after `source.start()`, not when the audio finished.

## Solution

### 1. Quote-optional regex for speech-to-text transcripts

Replace `'([^']+)'` (requires literal quotes) with `'?(.+?)'?` (optional quotes, lazy match) and add a `\s*\z` end-of-string anchor to prevent the lazy capture collapsing to a single character.

**Looping reminder (`app/services/command_parser.rb`):**

```ruby
# Before — requires literal single quotes that Deepgram strips
/\blooping\s+reminder\s+(?:for|every)\s+(\d+)\s+minutes?\s+saying\s+'([^']+)'\s+until\s+I\s+say\s+'([^']+)'/i

# After — quotes optional; \s*\z anchors the final lazy capture
/\blooping\s+reminder\s+(?:for|every)\s+(\d+)\s+minutes?\s+saying\s+'?(.+?)'?\s+until\s+I\s+say\s+'?(.+?)'?\s*\z/i
```

**Alias (`app/services/command_parser.rb`):**

```ruby
# Before
/\balias\s+'([^']+)'\s+as\s+'([^']+)'/i

# After — \s+as\s+ acts as natural separator between the two lazy captures
/\balias\s+'?(.+?)'?\s+as\s+'?(.+?)'?\s*\z/i
```

**Why `\s*\z` is critical:**
Without the end-of-string anchor, the lazy `.+?` satisfies at the shortest possible match — often a single character — when no closing quote is present. `\z` forces the last lazy group to consume the remainder of the string, making the boundary unambiguous.

**Without-quotes test added (`spec/services/command_parser_spec.rb`):**

```ruby
context "without quotes around message and stop phrase (as transcribed by speech-to-text)" do
  it "parses the command without quotes" do
    result = parser.parse("set looping reminder every 2 minutes saying did you sleep until i say sleeping")

    expect(result[:intent]).to eq(:create_loop)
    expect(result[:params][:interval_minutes]).to eq(2)
    expect(result[:params][:message]).to eq("did you sleep")
    expect(result[:params][:stop_phrase]).to eq("sleeping")
  end
end
```

---

### 2. X-Status-Text header pattern for on-screen TTS response text

The controller sets a custom `X-Status-Text` response header containing the spoken text. The Stimulus controller reads it before consuming the `ArrayBuffer` body and displays it while audio plays, resetting to "Ready" via `source.onended`.

**Controller — blank transcript case (`app/controllers/voice_commands_controller.rb`):**

```ruby
BLANK_TRANSCRIPT_MESSAGE = "Sorry, I didn't catch that.  Please try again."

if transcript.blank?
  audio_bytes = ElevenLabsClient.new.synthesize(
    text: BLANK_TRANSCRIPT_MESSAGE,
    voice_id: current_user.elevenlabs_voice_id
  )
  response.set_header("X-Status-Text", BLANK_TRANSCRIPT_MESSAGE)
  return send_data audio_bytes, type: "audio/mpeg", disposition: "inline"
end
```

**Controller — unknown intent case:**

```ruby
# app/services/command_responder.rb
UNKNOWN_INTENT_MESSAGE = "Sorry, I didn't understand that.  Please see the list of commands for voice commands I will understand."

# app/controllers/voice_commands_controller.rb
audio_bytes = CommandResponder.new.respond(command: parsed, user: current_user)
command.update!(status: "processed")
if parsed[:intent] == :unknown
  response.set_header("X-Status-Text", CommandResponder::UNKNOWN_INTENT_MESSAGE)
end
send_data audio_bytes, type: "audio/mpeg", disposition: "inline"
```

**Stimulus controller (`app/javascript/controllers/voice_controller.js`):**

```javascript
async postAudio(blob) {
  const token = document.querySelector("meta[name='csrf-token']")?.content
  const form = new FormData()
  form.append("audio", blob, "recording.webm")
  try {
    const resp = await fetch("/voice_commands", {
      method: "POST",
      headers: { "X-CSRF-Token": token },
      body: form
    })
    if (!resp.ok) throw new Error(`Server error: ${resp.status}`)
    const statusText = resp.headers.get("X-Status-Text")  // read before arrayBuffer()
    const buffer = await resp.arrayBuffer()
    this.playAudio(buffer, statusText)
  } catch (e) {
    this.updateStatus(`Error: ${e.message}`)
  }
}

async playAudio(arrayBuffer, statusText = null) {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)()
    const decoded = await ctx.decodeAudioData(arrayBuffer)
    const source = ctx.createBufferSource()
    source.buffer = decoded
    source.connect(ctx.destination)
    source.onended = () => this.updateStatus("Ready")   // resets AFTER audio finishes
    source.start()
    this.updateStatus(statusText || "Ready")            // shows text as audio begins
  } catch (e) {
    this.updateStatus("Audio playback failed")
  }
}
```

**Key design decisions:**
- `X-Status-Text` is read **before** `resp.arrayBuffer()` — headers remain accessible after the stream is consumed, but reading them first is the correct ordering
- Message constants are defined in Ruby so the TTS text and the on-screen text are guaranteed identical — no risk of drift
- `source.onended` fires after the full audio clip finishes, so "Ready" only appears when appropriate
- Same-origin requests have no CORS restriction on custom response headers

## Prevention & Best Practices

### Rules for writing regex patterns for voice/STT input

**Core principle: STT output is punctuation-free prose. Match what the recogniser returns, not what the user literally says.**

- **Never use `'([^']+)'`** to delimit spoken phrases. Deepgram and similar APIs strip single quotes, double quotes, and most punctuation.
- **Use keyword anchors** instead of punctuation anchors:

  ```ruby
  # Bad — will never match Deepgram output
  /alias '(?<name>[^']+)' as '(?<label>[^']+)'/

  # Good — anchors on the spoken keywords "alias" and "as"
  /\balias\s+'?(?<name>.+?)'?\s+as\s+'?(?<label>.+?)'?\s*\z/i
  ```

- **Always add `\s*\z`** when the final capture group is a lazy `.+?` with no closing delimiter.
- **Write test fixtures without punctuation** around spoken phrases — if your fixture has `'quotes'`, it is wrong.
- **Write a comment** documenting the spoken phrasing that the regex targets.

### Adding a new voice response that shows on screen

1. Define the response string as a Ruby constant (in the controller or service that generates it).
2. Pass it to `ElevenLabsClient#synthesize` (or `CommandResponder`).
3. Call `response.set_header("X-Status-Text", CONSTANT)` before `send_data`.
4. The Stimulus controller already reads `X-Status-Text` — no JS changes needed for new cases.

### Testing checklist for new voice commands

**Regex / parsing layer**
- [ ] Fixture strings contain no punctuation around spoken phrases (matches real Deepgram output)
- [ ] Pattern does NOT match when a required keyword is missing
- [ ] Mixed case and extra internal whitespace are handled
- [ ] Sub-phrase captures (name, label, etc.) are asserted individually

**Controller / endpoint layer**
- [ ] Happy path returns 200 with `audio/mpeg` content
- [ ] `X-Status-Text` header is present and correct when a response message is expected
- [ ] Blank transcript input returns 200 with audio + `X-Status-Text` (not 204 or 400)
- [ ] Unrecognised command returns `X-Status-Text` with the fallback message

**Mutation testing**
- Run mutant against `CommandParser#<new_method>` and kill all survivors before opening a PR

### When to use X-Status-Text vs alternatives

| Situation | Pattern |
|---|---|
| Transient operational state ("Listening…", "Processing…") | `X-Status-Text` header read by Stimulus |
| Voice command result the user must read | `X-Status-Text` for short status messages during audio |
| TTS message string and on-screen text must stay in sync | Define a Ruby constant, use for both |
| Response involves DOM changes beyond a status line | Turbo Stream broadcast |

## Related Documentation

### Existing solution docs

- [`docs/solutions/logic-errors/command-parser-spoken-time-parsing-bugs.md`](../logic-errors/command-parser-spoken-time-parsing-bugs.md) — Previous Deepgram regex bugs (spoken time parsing); same root cause pattern
- [`docs/solutions/integration-issues/empty-webm-audio-deepgram-400-corrupt-data.md`](empty-webm-audio-deepgram-400-corrupt-data.md) — Deepgram 400 from empty/corrupt WebM; relates to the blank-transcript branch
- [`docs/solutions/integration-issues/elevenlabs-tts-colon-zero-zero-sounds-like-hundred.md`](elevenlabs-tts-colon-zero-zero-sounds-like-hundred.md) — ElevenLabs TTS string formatting bugs
- [`docs/solutions/ui-bugs/turbo-streams-ordered-insertion-broadcast-before-to.md`](../ui-bugs/turbo-streams-ordered-insertion-broadcast-before-to.md) — Turbo Streams real-time UI update patterns

### Plans

- [`docs/plans/2026-02-25-feat-looping-reminders-plan.md`](../../plans/2026-02-25-feat-looping-reminders-plan.md) — Feature plan where both issues were discovered
