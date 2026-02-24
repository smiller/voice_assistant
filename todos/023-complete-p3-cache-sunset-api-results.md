---
status: pending
priority: p3
issue_id: "023"
tags: [code-review, performance, rails]
dependencies: []
---

# Cache Sunset API Results

## Problem Statement

Every "when is sunset" query calls the `sunrise-sunset.org` API synchronously in the request cycle. The sunset time for a given lat/lng changes by at most a minute or two per day. There is no reason to hit the external API more than once per day per location. Without caching, repeated queries (or multiple users at the same location) each incur a network round-trip and count against the public API rate limits.

## Findings

In `app/services/command_responder.rb`:

```ruby
when :sunset
  sunset = SunriseSunsetClient.new.sunset_time(lat: user.lat, lng: user.lng)
```

`SunriseSunsetClient` has no caching layer. Each call makes a fresh `Net::HTTP.get_response` to `api.sunrise-sunset.org`.

The `sunrise-sunset.org` API is a free public API with no authentication — rate limiting or downtime would silently break the feature.

## Proposed Solutions

### Option A: Cache in `CommandResponder` with Rails.cache (Recommended)

```ruby
when :sunset
  cache_key = "sunset/#{user.lat.round(2)}/#{user.lng.round(2)}/#{Date.current}"
  sunset = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
    SunriseSunsetClient.new.sunset_time(lat: user.lat, lng: user.lng)
  end
```

Rounds lat/lng to 2 decimal places (~1 km precision) so nearby users share the cache. Expires hourly (sunset changes negligibly within an hour).

**Pros:** Simple, uses existing Rails.cache, covers all users at similar locations
**Cons:** Requires cache serialization to work with `Time` objects (use `.to_i` and back)
**Effort:** Small
**Risk:** Low

### Option B: Cache inside `SunriseSunsetClient`

Inject `cache:` into the client and cache inside `sunset_time`.

**Pros:** Encapsulation — cache is colocated with the API call
**Cons:** Requires refactoring the client (also covered in todo #014)
**Effort:** Small
**Risk:** Low

## Acceptance Criteria

- [ ] Repeated "when is sunset" calls for the same location do not make multiple HTTP requests
- [ ] Cache expires by end of day (or within 1 hour)
- [ ] Spec verifies caching behavior
- [ ] RuboCop clean

## Work Log

- 2026-02-23: Identified during code review
