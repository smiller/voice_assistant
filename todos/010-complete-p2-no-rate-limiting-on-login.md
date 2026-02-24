---
status: pending
priority: p2
issue_id: "010"
tags: [code-review, security]
---

# Add Rate Limiting to Login Endpoint

## Problem Statement
`POST /session` has no throttling. An attacker can attempt passwords at full server speed with no limit. No account lockout exists. bcrypt provides ~100ms/hash slowdown but automated tools can still attempt thousands/hour against a remote target.

## Findings
- `app/controllers/sessions_controller.rb`: no rate limiting
- `User.find_by(email:).authenticate(password:)` — no lockout mechanism
- Gemfile: `rack-attack` not present

## Proposed Solutions

### Option A: Add rack-attack (Recommended)
```ruby
# Gemfile
gem "rack-attack"

# config/initializers/rack_attack.rb
Rack::Attack.throttle("logins/ip", limit: 5, period: 20) do |req|
  req.ip if req.path == "/session" && req.post?
end
Rack::Attack.throttle("logins/email", limit: 5, period: 20) do |req|
  req.params["email"].to_s.downcase if req.path == "/session" && req.post?
end
```
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] `rack-attack` gem added and configured
- [ ] Login endpoint throttled by IP and email
- [ ] Returns 429 after exceeding threshold
- [ ] Legitimate users with normal usage are not affected

## Work Log
- 2026-02-23: Identified by security-sentinel during code review
