---
status: pending
priority: p3
issue_id: "027"
tags: [code-review, agent-native, architecture]
dependencies: []
---

# Agent-Native Access Gaps: No Text API, No Token Auth, No Reminder CRUD

## Problem Statement

The app has zero agent-accessible capabilities. Every user action (send voice command, manage reminders) requires audio input, a live browser session, and cookie-based authentication. Agents (Claude Code, MCP tools, external integrations) cannot use the app at all. The agent-native reviewer found 9 capabilities with 0 agent-accessible equivalents.

## Findings

### 1. No text command API
`POST /voice_commands` accepts only multipart audio (`audio` field, Deepgram transcription required). There is no way to submit a text transcript directly — an agent can't say "set a timer for 5 minutes" without synthesizing audio first.

### 2. No token-based authentication
The app uses cookie sessions exclusively (`has_secure_password` + session cookie). Agents cannot obtain or use a session cookie. There is no API key, bearer token, or JWT endpoint.

### 3. No reminder CRUD API
There are no endpoints to list, create, update, or cancel reminders programmatically. An agent cannot inspect what reminders exist or manage them.

## Proposed Solutions

### Option A: Add a minimal text command endpoint (Recommended first step)

```ruby
# POST /voice_commands/text
# Body: { transcript: "set a timer for 5 minutes" }
# Auth: Bearer token
```

This skips Deepgram entirely and feeds the transcript directly into `CommandResponder`. Low cost, high agent value.

**Pros:** Unblocks all agent use cases without audio
**Cons:** Requires token auth (see Option B)
**Effort:** Medium
**Risk:** Low

### Option B: Add API token authentication

Add a `User#api_token` column. Accept `Authorization: Bearer <token>` on JSON endpoints.

```ruby
# app/controllers/api/v1/base_controller.rb
def authenticate_user_from_token!
  token = request.headers["Authorization"]&.delete_prefix("Bearer ")
  @current_user = User.find_by(api_token: token) || unauthorized!
end
```

**Pros:** Enables all programmatic access
**Cons:** Token management (rotation, expiry) adds scope
**Effort:** Medium
**Risk:** Low

### Option C: Reminders API

`GET /api/v1/reminders` + `DELETE /api/v1/reminders/:id` to list and cancel reminders.

**Pros:** Enables agent-based reminder management
**Cons:** Depends on token auth (Option B first)
**Effort:** Medium
**Risk:** Low

## Acceptance Criteria

- [ ] At minimum: `POST /voice_commands/text` accepts a transcript and returns TTS audio or confirmation
- [ ] Endpoint protected with token auth (not cookie)
- [ ] Documented in README
- [ ] Agent can set a timer end-to-end without a browser

## Work Log

- 2026-02-23: Identified during code review
