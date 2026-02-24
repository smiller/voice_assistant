---
status: pending
priority: p2
issue_id: "014"
tags: [code-review, architecture, testing]
---

# Inject SunriseSunsetClient into CommandResponder Consistently

## Problem Statement
`ElevenLabsClient` is injected via `CommandResponder`'s constructor (enabling clean test doubles), but `SunriseSunsetClient` is instantiated directly inside `response_text` with `SunriseSunsetClient.new`. This inconsistency means the sunset spec must stub the class-level `.new` call rather than injecting a double — a weaker form of isolation.

## Findings
- `app/services/command_responder.rb` line 3: `def initialize(tts_client: ElevenLabsClient.new)` — injected
- `app/services/command_responder.rb` line 22: `SunriseSunsetClient.new.sunset_time(...)` — hardcoded
- `spec/services/command_responder_spec.rb`: uses `allow(SunriseSunsetClient).to receive(:new).and_return(...)` — class stub, not injection

## Proposed Solutions

### Option A: Add geo_client to constructor (Recommended)
```ruby
def initialize(tts_client: ElevenLabsClient.new, geo_client: SunriseSunsetClient.new)
  @tts_client = tts_client
  @geo_client = geo_client
end
```
Replace `SunriseSunsetClient.new.sunset_time(...)` with `@geo_client.sunset_time(...)`. Update spec to inject `instance_double(SunriseSunsetClient)`.
- Effort: Small | Risk: None

## Acceptance Criteria
- [ ] `SunriseSunsetClient` injected via constructor parameter
- [ ] Sunset spec uses `instance_double` injection rather than class stub
- [ ] All existing sunset tests pass

## Work Log
- 2026-02-23: Identified by architecture-strategist during code review
