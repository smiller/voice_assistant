---
status: pending
priority: p3
issue_id: "019"
tags: [code-review, quality, rails]
dependencies: []
---

# No-Op `rescue; raise` in API Clients

## Problem Statement

All three API client classes (`DeepgramClient`, `ElevenLabsClient`, `SunriseSunsetClient`) contain `rescue => e; raise` patterns that catch errors and immediately re-raise them unchanged. This is dead code — it adds noise and obscures intent. Either handle the error (wrap it, log it, translate it) or remove the rescue entirely.

## Findings

Pattern present in all three clients:

```ruby
rescue => e
  raise e
```

Or equivalently:

```ruby
rescue => e
  raise
```

This is a no-op. The exception propagates identically with or without the rescue block. The only effect is that it hides the original backtrace line from the net/http call.

## Proposed Solutions

### Option A: Remove the rescue blocks entirely (Recommended)

Let exceptions propagate naturally. Callers (`CommandResponder`, `VoiceCommandsController`) are responsible for handling network errors.

**Pros:** Simpler, cleaner, preserves full backtraces
**Cons:** None
**Effort:** Small (delete 2 lines × 3 files)
**Risk:** None (behavior unchanged)

### Option B: Wrap in a domain error

If callers need to catch a specific error type:

```ruby
rescue => e
  raise ApiError, "ElevenLabs request failed: #{e.message}"
end
```

**Pros:** Encapsulates network details behind a domain error
**Cons:** Requires callers to handle `ApiError`; more scope than needed now
**Effort:** Medium
**Risk:** Low

## Acceptance Criteria

- [ ] No bare `rescue => e; raise` patterns in any API client
- [ ] Existing tests still pass
- [ ] RuboCop clean

## Work Log

- 2026-02-23: Identified during code review
