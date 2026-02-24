---
status: pending
priority: p2
issue_id: "015"
tags: [code-review, security, reliability]
---

# Fix SunriseSunsetClient SSL Enforcement and HTTP Success Check

## Problem Statement
`SunriseSunsetClient` uses `Net::HTTP.get_response` (implicit SSL) unlike `DeepgramClient` and `ElevenLabsClient` which use explicit `Net::HTTP.start(..., use_ssl: true)`. It also has no HTTP success check before parsing the response body — a 5xx response's error JSON or HTML body will raise `JSON::ParserError` instead of a meaningful `SunriseSunsetClient::Error`.

## Findings
- `app/services/sunrise_sunset_client.rb` line 26: `Net::HTTP.get_response(uri)` — no explicit SSL
- No `response.is_a?(Net::HTTPSuccess)` check before `JSON.parse(response.body)`
- `DeepgramClient` and `ElevenLabsClient` both check response status before parsing
- `JSON::ParserError` on non-JSON response body bypasses the typed error wrapper

## Proposed Solutions

### Option A: Match other client patterns (Recommended)
```ruby
def fetch(lat:, lng:)
  uri = URI(BASE_URL)
  uri.query = URI.encode_www_form(lat: lat, lng: lng, formatted: 0)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
    http.get(uri.request_uri)
  end
  raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
rescue JSON::ParserError => e
  raise Error, "Invalid response: #{e.message}"
end
```
- Effort: Small | Risk: None

## Acceptance Criteria
- [ ] `SunriseSunsetClient` uses explicit `use_ssl: true`
- [ ] Non-2xx responses raise `SunriseSunsetClient::Error`
- [ ] Non-JSON responses raise `SunriseSunsetClient::Error`
- [ ] Existing sunset specs pass

## Work Log
- 2026-02-23: Identified by rails-reviewer, security-sentinel, architecture-strategist during code review
