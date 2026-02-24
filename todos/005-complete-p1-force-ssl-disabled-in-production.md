---
status: complete
priority: p1
issue_id: "005"
tags: [code-review, security, production]
---

# Enable force_ssl in Production

## Problem Statement
`config.force_ssl = true` is commented out in `config/environments/production.rb`. Without it: Rails does not redirect HTTP to HTTPS, session cookies lack the `Secure` flag (transmittable over plain HTTP), and no HSTS header is emitted. This enables trivial session hijacking on any unencrypted network.

## Findings
- `config/environments/production.rb`: both `config.assume_ssl` and `config.force_ssl` are commented out
- Session cookie transmitted over plain HTTP → interceptable by network attacker
- Login form credentials transmittable in plaintext
- No HSTS header prevents browser from enforcing HTTPS on repeat visits

## Proposed Solutions

### Option A: Enable force_ssl (Recommended)
Uncomment `config.force_ssl = true`. If Rails runs behind an SSL-terminating reverse proxy, also uncomment `config.assume_ssl = true`.
- Effort: Small (2-line uncomment) | Risk: Low

### Option B: Handle at reverse proxy only
Configure nginx/Caddy to redirect HTTP→HTTPS. Still uncomment `assume_ssl: true` so Rails sets Secure cookie flag.
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] `config.force_ssl = true` uncommented
- [ ] Session cookies have `Secure` flag set in production
- [ ] HTTPS redirect works; plain HTTP requests redirect to HTTPS

## Work Log
- 2026-02-23: Identified by security-sentinel during code review
