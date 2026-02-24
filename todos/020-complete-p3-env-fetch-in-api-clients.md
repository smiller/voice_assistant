---
status: pending
priority: p3
issue_id: "020"
tags: [code-review, quality, rails]
dependencies: []
---

# Use `ENV.fetch` Instead of `ENV[]` in API Clients

## Problem Statement

All API clients read environment variables with `ENV["KEY"]`, which silently returns `nil` if the variable is missing. This causes confusing downstream errors (e.g., `Net::HTTPBadResponse` or `401 Unauthorized`) instead of a clear startup failure. `ENV.fetch` raises `KeyError` with the variable name when the key is absent, making misconfiguration immediately obvious.

## Findings

Pattern in `DeepgramClient`, `ElevenLabsClient`, `SunriseSunsetClient`:

```ruby
api_key = ENV["DEEPGRAM_API_KEY"]  # returns nil silently
```

Should be:

```ruby
api_key = ENV.fetch("DEEPGRAM_API_KEY")  # raises KeyError if missing
```

Rails credentials or `config/application.yml` (Figaro) would be a longer-term improvement, but `ENV.fetch` is the minimal fix.

## Proposed Solutions

### Option A: Replace `ENV[]` with `ENV.fetch` (Recommended)

Three files, one line each. No behavioral change when variables are present.

**Pros:** Fail-fast, clear error message, minimal change
**Cons:** None
**Effort:** Small
**Risk:** None

### Option B: Centralize in an initializer

```ruby
# config/initializers/env_check.rb
%w[DEEPGRAM_API_KEY ELEVENLABS_API_KEY].each do |key|
  raise "Missing env var: #{key}" unless ENV.key?(key)
end
```

**Pros:** Single place for all checks, runs at startup
**Cons:** More indirection, slightly more scope
**Effort:** Small
**Risk:** Low

## Acceptance Criteria

- [ ] All `ENV["KEY"]` reads in API clients replaced with `ENV.fetch("KEY")`
- [ ] Tests for missing keys confirm `KeyError` is raised
- [ ] RuboCop clean

## Work Log

- 2026-02-23: Identified during code review
