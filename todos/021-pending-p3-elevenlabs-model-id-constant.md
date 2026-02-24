---
status: pending
priority: p3
issue_id: "021"
tags: [code-review, quality, rails]
dependencies: []
---

# ElevenLabs `model_id` Magic String → Named Constant

## Problem Statement

`ElevenLabsClient` hardcodes the ElevenLabs model identifier (e.g., `"eleven_turbo_v2_5"`) as a magic string inline. When ElevenLabs releases a new model or the team wants to switch, the string must be hunted down in the code. A named constant makes the value self-documenting and easy to update.

## Findings

In `app/services/elevenlabs_client.rb`, the model ID is embedded directly in the request body hash:

```ruby
model_id: "eleven_turbo_v2_5"
```

No other reference; changing the model means touching the implementation internals.

## Proposed Solutions

### Option A: Private constant in the class (Recommended)

```ruby
class ElevenLabsClient
  MODEL = "eleven_turbo_v2_5"

  private_constant :MODEL
  ...
  model_id: MODEL
```

**Pros:** Self-documenting, single source of truth, easy to grep
**Cons:** None
**Effort:** Trivial
**Risk:** None

### Option B: Make model configurable via initializer

```ruby
def initialize(api_key: ENV.fetch("ELEVENLABS_API_KEY"), model: "eleven_turbo_v2_5")
  @model = model
```

**Pros:** Allows per-call model override for testing or A/B comparison
**Cons:** Slight over-engineering if only one model is ever used
**Effort:** Small
**Risk:** Low

## Acceptance Criteria

- [ ] Model ID string lives in a named constant
- [ ] ElevenLabsClient spec passes unchanged
- [ ] RuboCop clean

## Work Log

- 2026-02-23: Identified during code review
