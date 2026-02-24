---
status: pending
priority: p2
issue_id: "009"
tags: [code-review, security]
---

# Enable Content Security Policy

## Problem Statement
The entire CSP configuration in `config/initializers/content_security_policy.rb` is commented out. No `Content-Security-Policy` header is sent to browsers. Any XSS vulnerability can be trivially escalated — injected scripts run without restriction, can exfiltrate CSRF tokens, make arbitrary fetch calls, and read DOM content.

## Findings
- `config/initializers/content_security_policy.rb`: entire block commented out
- `app/views/layouts/application.html.erb` calls `<%= csp_meta_tag %>` but emits nothing without a policy
- Application loads inline scripts via importmap, communicates with Deepgram and ElevenLabs origins

## Proposed Solutions

### Option A: Enable with nonce-based script-src (Recommended)
Configure CSP with nonces for importmap compatibility:
```ruby
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.script_src  :self, :nonce
  policy.connect_src :self, "https://api.deepgram.com", "https://api.elevenlabs.io"
  policy.object_src  :none
  policy.base_uri    :self
end
Rails.application.config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
```
- Effort: Medium | Risk: Medium (may break things requiring nonce adjustment)

## Acceptance Criteria
- [ ] CSP header present on all responses
- [ ] `script-src` uses nonce for importmap compatibility
- [ ] No console CSP violations in normal app usage
- [ ] `object-src: none` prevents plugin-based XSS

## Work Log
- 2026-02-23: Identified by security-sentinel during code review
