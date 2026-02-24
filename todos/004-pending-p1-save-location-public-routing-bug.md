---
status: pending
priority: p1
issue_id: "004"
tags: [code-review, rails, routing]
---

# Make SessionsController#save_location Private

## Problem Statement
`save_location` is defined as a public method on `SessionsController` without a `private` keyword, making it a routable Rails action. A request to `GET /sessions/save_location` will be routed to it, which will raise `ArgumentError` (wrong number of arguments) since the method requires a `user` argument. This is a latent 500 error surface.

## Findings
- `app/controllers/sessions_controller.rb` line 16: `def save_location(user)` — no `private` above it
- Called only once in `create` (line 11) — not an action, never intended to be public
- Rails routes any public controller method as an action
- `GET /sessions/save_location` → ArgumentError → 500

## Proposed Solutions

### Option A: Add private keyword (Recommended)
```ruby
def create; end
def destroy; end

private

def save_location(user)
  return if params[:lat].blank? || params[:lng].blank?
  return if user.lat.present? || user.lng.present?
  user.update!(lat: params[:lat], lng: params[:lng])
end
```
- Effort: Small | Risk: None

### Option B: Inline into create
The method is 4 lines and called once. Inline it directly into `create`, eliminating the helper method entirely.
- Effort: Small | Risk: None

## Acceptance Criteria
- [ ] `save_location` is no longer a public controller action
- [ ] `GET /sessions/save_location` no longer routes to it
- [ ] Login + geolocation saving still works

## Work Log
- 2026-02-23: Identified by rails-reviewer, architecture-strategist, simplicity-reviewer
