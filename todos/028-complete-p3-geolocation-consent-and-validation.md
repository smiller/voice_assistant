---
status: pending
priority: p3
issue_id: "028"
tags: [code-review, security, rails]
dependencies: []
---

# Geolocation: Silent Collection Without Consent or Server-Side Validation

## Problem Statement

The app silently collects the user's geolocation (lat/lng) via `navigator.geolocation` on first login and saves it via `PATCH /settings/location` (or equivalent). There is no user-visible consent notice beyond the browser's native permission dialog. Additionally, the `save_location` action stores raw lat/lng from the client without server-side range validation — values like `lat: 999` or `lng: -9999` would be accepted.

## Findings

1. **No explicit consent UI**: The geolocation request fires automatically after login. Users see only the browser's OS-level permission prompt, with no explanation of why the app needs their location.

2. **No server-side validation**: `User#lat` and `User#lng` columns have no range checks. The browser sends whatever coordinates the JS provides; the model or controller does not validate:
   - Latitude: must be between -90.0 and 90.0
   - Longitude: must be between -180.0 and 180.0

3. **GDPR/CCPA consideration**: Location data is PII in most jurisdictions. Silent collection without explicit consent may create compliance exposure if the app is used outside the US.

## Proposed Solutions

### Option A: Add model validations (Recommended minimal fix)

```ruby
# app/models/user.rb
validates :lat, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
validates :lng, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
```

**Pros:** Prevents bad data, minimal change
**Cons:** Doesn't address consent
**Effort:** Trivial
**Risk:** None

### Option B: Add consent notice in the UI

Display a banner before triggering geolocation: "We use your location to show accurate sunset times. [Allow] [Skip]"

**Pros:** Explicit consent, better UX, GDPR-friendlier
**Cons:** UI change required
**Effort:** Small
**Risk:** Low

### Option C: Both (Recommended combined)

Apply validations immediately (Option A), add consent UI in a separate PR.

## Acceptance Criteria

- [ ] `User` validates lat in [-90, 90] and lng in [-180, 180]
- [ ] `save_location` returns 422 for out-of-range values
- [ ] Spec covers invalid lat/lng rejection
- [ ] (Stretch) Consent notice shown before geolocation is requested

## Work Log

- 2026-02-23: Identified during code review
