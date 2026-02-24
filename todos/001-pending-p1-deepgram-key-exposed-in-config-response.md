---
status: pending
priority: p1
issue_id: "001"
tags: [code-review, security]
---

# Remove Deepgram API Key from /config JSON Response

## Problem Statement
`ConfigController#show` serialises the live `DEEPGRAM_API_KEY` into a JSON response delivered to every authenticated browser session. The key is stored in a Stimulus controller property, visible in DevTools and network responses. Critically, `this.deepgramKey` is fetched and stored but **never used** anywhere in `voice_controller.js` — the exposure is entirely gratuitous. All transcription already happens server-side via `DeepgramClient`.

## Findings
- `app/controllers/config_controller.rb` lines 5–8: `deepgram_key: ENV.fetch("DEEPGRAM_API_KEY")` included in JSON
- `app/javascript/controllers/voice_controller.js` line 29: stored as `this.deepgramKey` but never read again
- Any authenticated user can `fetch('/config')` and extract the live key
- Impact: billing fraud, unlimited Deepgram API usage at owner's cost, key revocation causing outage

## Proposed Solutions

### Option A: Remove deepgram_key from response (Recommended)
Remove `deepgram_key` from the config JSON. The server already does all transcription. Nothing client-side needs it.
- Pros: Eliminates exposure entirely, 2-line fix
- Cons: None — the key is unused client-side
- Effort: Small | Risk: None

### Option B: Proxy Deepgram through server (already done)
The app already posts audio to `POST /voice_commands` which calls `DeepgramClient` server-side. No change needed beyond removing the key from /config.
- This is the current architecture — Option A is sufficient

## Acceptance Criteria
- [ ] `deepgram_key` removed from `ConfigController#show` response
- [ ] `voice_controller.js` `loadConfig` either removed or reduced to fetch only `voice_id`
- [ ] No authenticated request can retrieve `DEEPGRAM_API_KEY`

## Work Log
- 2026-02-23: Identified by security-sentinel and architecture-strategist agents during code review
