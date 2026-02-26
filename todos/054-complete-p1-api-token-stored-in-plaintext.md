---
status: complete
priority: p1
issue_id: "054"
tags: [code-review, security, api, authentication]
dependencies: []
---

# API Token Stored in Plaintext — Use `has_secure_token` or Hashed Storage

## Problem Statement

`User#api_token` is a plain `string` column with a unique index. If the database or a backup is ever read by an unauthorized party, every user's API token is immediately usable to authenticate as that user. Tokens should be stored hashed (like passwords) or generated fresh each time via Rails' `has_secure_token`, which at minimum makes token values unreadable at rest.

Additionally, `authenticate_from_token!` uses `find_by(api_token: token)`, which performs a direct equality lookup. A constant-time comparison is not used, and token comparison happens implicitly in SQL rather than in application code, leaving the door open to timing side-channels at the application layer if caching or database row structure leaks vary by existence.

## Findings

- `db/schema.rb` — `t.string "api_token"` with unique index; no indication of hashing.
- `app/controllers/api/v1/base_controller.rb:9-11` — `find_by(api_token: token)` with no `SecureCompare`; `head :unauthorized` on nil without constant-time exit.
- `app/models/user.rb` — no `has_secure_token :api_token` declaration.
- Identified by security-sentinel (P1).

## Proposed Solutions

### Option A: Switch to `has_secure_token` (Recommended)

Rails `has_secure_token` generates a cryptographically random token on first save and optionally supports token hashing (Rails 7.1+). With hashing enabled, only a SHA-256 digest is stored.

```ruby
# app/models/user.rb
has_secure_token :api_token

# Rails 7.1+ with hashing:
has_secure_token :api_token, digest: true
# Stores api_token_digest; find_by must use authenticate_api_token
```

For `digest: true`, update `authenticate_from_token!`:
```ruby
def authenticate_from_token!
  token = request.headers["Authorization"]&.delete_prefix("Bearer ")
  @current_user = token && User.find_by(api_token_digest: OpenSSL::Digest::SHA256.hexdigest(token))
  head :unauthorized unless @current_user
end
```

**Pros:** Tokens unreadable at rest; Rails idiomatic; easy to rotate (call `user.regenerate_api_token`).
**Cons:** Migration required to rename/repopulate column; existing tokens invalidated on deploy.

**Effort:** 2 hours
**Risk:** Low — breaking change only for any existing API consumers (co-ordinate with deploy)

---

### Option B: Hash with SHA-256 manually without `has_secure_token`

Store `api_token_digest` and verify with `SecureCompare`.

**Pros:** Works on any Rails version.
**Cons:** More hand-rolled code; `has_secure_token` already provides this cleanly.

**Effort:** 2.5 hours
**Risk:** Low

---

### Option C: Token-as-bearer with `SecureRandom.hex` + `secure_compare`

Keep plain token but add `ActiveSupport::SecurityUtils.secure_compare` in the controller. Does not fix at-rest exposure.

**Pros:** Minimal change.
**Cons:** Tokens still readable in DB; does not address the core finding.

**Effort:** 30 minutes
**Risk:** Low (but insufficient)

## Recommended Action

Option A with `digest: true` (Rails 7.1+). Migrate `api_token` → `api_token_digest`, invalidate old tokens, and update `authenticate_from_token!` to hash-lookup. Co-ordinate with any API consumers before deploying.

## Technical Details

**Affected files:**
- `app/models/user.rb` — add `has_secure_token :api_token, digest: true`
- `app/controllers/api/v1/base_controller.rb` — update lookup
- `db/migrate/` — rename column or add digest column
- `db/schema.rb` — will reflect migration

## Acceptance Criteria

- [ ] `api_token` value not readable in plaintext from `users` table
- [ ] Authentication still works end-to-end
- [ ] Token rotation possible via `user.regenerate_api_token`
- [ ] Spec covers invalid token → 401
- [ ] RuboCop clean

## Work Log

- 2026-02-26: Identified by security-sentinel during final PR review.
- 2026-02-26: Fixed by implementing manual digest storage (has_secure_token digest: true not available in this Rails build). Migration: api_token → api_token_digest (SHA-256 hex). Model: generate_api_token callback, authenticate_api_token, regenerate_api_token, find_by_api_token, digest_api_token. Controller: uses find_by_api_token with secure_compare-based lookup.
