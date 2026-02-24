---
title: "Empty WebM Audio Blob Causes Deepgram 400 'Corrupt or Unsupported Data'"
date: 2026-02-24
category: integration-issues
tags:
  - deepgram
  - mediarecorder
  - webm
  - audio
  - stimulus
  - error-handling
  - railway
symptoms:
  - "Deepgram returns HTTP 400: 'Bad Request: failed to process audio: corrupt or unsupported data'"
  - "Audio payload is only ~110 bytes (WebM container header, no audio frames)"
  - "VoiceCommandsController returns 500 when DeepgramClient::Error is raised"
  - "No error details in logs — API failures are silently re-raised"
components:
  - DeepgramClient
  - VoiceCommandsController
  - voice_controller.js (Stimulus)
  - Browser MediaRecorder API
severity: high
resolved: true
resolution_time: "2–4 hours"
---

# Empty WebM Audio Blob Causes Deepgram 400 "Corrupt or Unsupported Data"

## Root Cause

MediaRecorder initialization is asynchronous — `getUserMedia` must resolve before recording
actually begins. When a user presses and releases the spacebar quickly, the keyup event fires
before the MediaRecorder has buffered any audio frames. The result is a valid WebM container
header (~110 bytes) with no audio payload, which Deepgram rejects with HTTP 400.

A secondary issue: `DeepgramClient::Error` was not rescued in the controller, so Deepgram
failures always surfaced as 500s, and no error details were logged.

## Investigation Path

1. Added structured error logging to `DeepgramClient` (HTTP status, response body, exception
   class/message) — immediately revealed the exact Deepgram error in production logs.
2. Added `rescue DeepgramClient::Error` in `VoiceCommandsController` → 422 instead of 500.
3. Attempted Content-Type fix (`audio/webm` → `audio/webm;codecs=opus`) — eliminated as the
   cause (audio was structurally empty regardless of Content-Type).
4. Added payload size logging (`audio.bytesize`) — revealed 110-byte payloads.
5. Confirmed root cause: race between async MediaRecorder startup and a brief spacebar tap.

## What Didn't Work (and Why)

**Content-Type change (`audio/webm` → `audio/webm;codecs=opus`)** — did not fix the issue
because the problem was not a MIME type mismatch. Deepgram was receiving a structurally empty
file; the codec hint is irrelevant when the audio data section of the container is absent.

## Solution

Both layers need a guard. The client prevents the recorder from stopping before it has had
time to buffer real audio; the server rejects obviously-empty payloads before calling Deepgram.

### 1. Log errors in external API clients

`app/services/deepgram_client.rb` (same pattern for `ElevenLabsClient`):

```ruby
unless response.is_a?(Net::HTTPSuccess)
  Rails.logger.error("DeepgramClient error: #{response.code} #{response.body}")
  raise Error
end
rescue Error
  raise
rescue StandardError => e
  Rails.logger.error("DeepgramClient error: #{e.class}: #{e.message}")
  raise Error
```

### 2. Rescue vendor errors in the controller

`app/controllers/voice_commands_controller.rb`:

```ruby
def create
  # ...
rescue DeepgramClient::Error
  head :unprocessable_entity
end
```

### 3. Server-side minimum payload size guard

```ruby
return head :unprocessable_entity if audio.size < 1.kilobyte
```

Add this before the Deepgram call. A valid WebM with audio frames is always > 1 KB at any
realistic bitrate (Opus at 8 kbps → ~1 KB/s).

### 4. Client-side minimum recording duration

`app/javascript/controllers/voice_controller.js`:

```javascript
MIN_DURATION_MS = 500

// In startRecording(), after mediaRecorder.start():
this.recordingStartedAt = Date.now()

// In stopRecording(), before calling mediaRecorder.stop():
const elapsed = Date.now() - this.recordingStartedAt
if (elapsed < this.MIN_DURATION_MS) {
  this.autoStopTimeout = setTimeout(
    () => this.stopRecording(),
    this.MIN_DURATION_MS - elapsed
  )
  return
}
```

The deferred stop ensures the recorder always buffers at least 500ms of audio before the
stream closes.

## Prevention Strategies

- **Use `onstart` event, not promise resolution, to set the "recording" flag.** `getUserMedia`
  resolving does not mean the MediaRecorder is in the `recording` state. Check
  `MediaRecorder.state === 'recording'` or wait for the `onstart` event before enabling stop.
- **Check `MediaRecorder.state` before calling `stop()`.** Calling `stop()` on a recorder that
  hasn't started produces an empty blob.
- **Log input shape, not just outcome.** Logging `audio.bytesize` immediately made the root
  cause obvious. Without it, the 110-byte payload would have been invisible.
- **Translate vendor errors at the client boundary.** Wrap external API calls in typed error
  classes and rescue them explicitly in controllers. Never let raw vendor HTTP failures surface
  as 500s.

## Testing Recommendations

**Rails (RSpec):**

```ruby
# Server-side size guard
it "returns 422 when audio is smaller than 1 KB" do
  tiny = Rack::Test::UploadedFile.new(
    StringIO.new("x" * (1.kilobyte - 1)), "audio/webm", original_filename: "tiny.webm"
  )
  post "/voice_commands", params: { audio: tiny }
  expect(response).to have_http_status(:unprocessable_entity)
end

# Vendor error → 422
context "when DeepgramClient raises an error" do
  before { allow(deepgram).to receive(:transcribe).and_raise(DeepgramClient::Error) }

  it "returns 422 without creating a VoiceCommand" do
    expect { post "/voice_commands", params: { audio: audio_file } }
      .not_to change(VoiceCommand, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
```

**Fixture note:** All test audio fixtures must be `>= 1 KB`. Pad with null bytes if needed:
```ruby
let(:audio_data) { ("\xFF\xFB\x90\x00" + "x" * 1.kilobyte).b }
```

## Monitoring

- Log `audio.bytesize` before every Deepgram call. A sustained stream of small values
  indicates a client-side regression.
- Log HTTP status + response body on every vendor 4xx/5xx — distinguishes bad data (4xx)
  from vendor outages (5xx).
- Alert on elevated 422 rates from the audio endpoint as a proxy for empty-recording
  regressions.

## Generalizable Lessons

1. **Async initialization requires explicit readiness gates.** Any browser API with async setup
   (getUserMedia, WebSocket, WebRTC) must not allow user actions until the API signals
   readiness via a callback or state change — not just promise resolution.

2. **Structural validity ≠ content validity.** A file can have a valid header while containing
   no meaningful data. Guards must check both (MIME type + minimum payload size).

3. **Client and server guards are complementary, not redundant.** The client guard improves UX
   by failing fast. The server guard is the authoritative enforcement point regardless of client
   behavior. Both are required.

4. **External API errors must be translated at the boundary.** Catch them in the client wrapper,
   convert to typed application errors, and handle explicitly in controllers.
