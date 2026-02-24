---
title: "feat: Display Pending Timers and Reminders"
type: feat
status: active
date: 2026-02-24
origin: docs/brainstorms/2026-02-24-pending-timers-reminders-display-brainstorm.md
---

# feat: Display Pending Timers and Reminders

## Overview

Add a live panel to `voice_commands/index.html.erb` showing the user's pending timers and
reminders. Timers appear first with a live countdown, followed by one-time reminders, then
a daily reminders subsection. Items appear live when spoken and disappear when they fire.

## Proposed Solution

Inline rendering on the existing index page (no new controller or route). The existing
`turbo_stream_from current_user` subscription carries all live updates. A new Stimulus
`countdown` controller handles client-side ticking. Empty state is managed by a CSS
`:has()` rule — no JavaScript needed for placeholder show/hide.

(see brainstorm: docs/brainstorms/2026-02-24-pending-timers-reminders-display-brainstorm.md)

## Technical Considerations

### Broadcast ownership
`CommandResponder#schedule_reminder` broadcasts the `append` immediately after
`Reminder.create!`. This mirrors how `ReminderJob` already issues broadcasts and avoids
giving the controller knowledge of which Turbo target a given reminder belongs to.

### Daily reminder rescheduling
When `ReminderJob` creates the next occurrence, it also broadcasts an `append` for the new
record so the row reappears live. Without this a user keeping the page open all day would
see the daily reminder disappear at fire time and never reappear.

### Timer duration display
No `duration_minutes` column is needed. Derive from
`((reminder.fire_at - reminder.created_at) / 60).round` in the partial. This is accurate
because `fire_at = minutes.minutes.from_now` is computed at record creation time.

### Empty state
The placeholder is a `<li class="empty-state">` inside each `<ul>`. A CSS `:has()` rule
hides it when the list contains any real item. Works transparently with Turbo Stream
`append` and `remove` — no JS observer required.

### N+1 prevention
The index query uses `includes(:user)` so the partial's `reminder.user.timezone` call
does not hit the database per row. For broadcast-rendered rows (one at a time), the single
`reminder.user` load is acceptable.

## System-Wide Impact

- **Interaction graph**: `VoiceCommandsController#create` → `CommandResponder#respond` →
  `schedule_reminder` → `Reminder.create!` → `broadcast_append_to`. Also:
  `ReminderJob#perform` → `reminder.delivered!` → `broadcast_remove_to` + (if daily)
  `Reminder.create!` → `broadcast_append_to`.
- **Error propagation**: Broadcast calls are fire-and-forget via Action Cable. A failed
  broadcast does not affect the HTTP response or job outcome.
- **State lifecycle risks**: The page-load race (reminder fires between the index query
  and the Turbo subscription becoming active) is accepted. For timers, the Stimulus
  auto-hide at zero is a fallback; for reminders, a page reload corrects stale rows. The
  `turbo_stream_from` tag renders before the item list so the subscription is active
  before the initial items render.
- **API surface parity**: No agent-facing surface added; this is display-only.

## Acceptance Criteria

- [ ] `GET /voice_commands` assigns `@timers`, `@reminders`, `@daily_reminders` scoped to
  `current_user.reminders.pending`, ordered by `fire_at`
- [ ] Panel renders all three sections; each shows placeholder text when empty
- [ ] Speaking a timer appends a live countdown row to `#timers`
- [ ] Speaking a reminder appends a row to `#reminders`
- [ ] Speaking a daily reminder appends a row to `#daily_reminders`
- [ ] When a reminder fires, its row is removed from the panel
- [ ] When a daily reminder fires, the rescheduled occurrence appears live in
  `#daily_reminders`
- [ ] Timer rows show "Started H:MM AM/PM · N min timer" + live "M:SS remaining"
- [ ] Countdown reaches zero → row hidden client-side; Turbo remove arrives as a no-op
- [ ] `clearInterval` called in Stimulus `disconnect()` — no timer leak on DOM removal
- [ ] Reminder rows show "H:MM AM/PM — message"
- [ ] Empty state placeholder hides when items are present, reappears when list empties
- [ ] All new code passes RuboCop and mutant with no surviving mutants

## Implementation Steps

### Step 1 — Controller: load pending reminders for index

**`app/controllers/voice_commands_controller.rb`**
```ruby
def index
  pending = current_user.reminders.pending.includes(:user).order(:fire_at)
  @timers          = pending.timer
  @reminders       = pending.reminder
  @daily_reminders = pending.daily_reminder
end
```

**`spec/requests/voice_commands_spec.rb`** (or existing controller spec)
- `GET /voice_commands` assigns `@timers`, `@reminders`, `@daily_reminders` with correct
  scoping and ordering
- Each collection contains only records belonging to `current_user` with `pending` status

---

### Step 2 — View: add pending panel

**`app/views/voice_commands/index.html.erb`** — add below the `va-layout` div:
```erb
<section class="va-pending">
  <h2>Timers</h2>
  <ul id="timers">
    <%= render @timers %>
    <li class="empty-state">No active timers</li>
  </ul>

  <h2>Reminders</h2>
  <ul id="reminders">
    <%= render @reminders %>
    <li class="empty-state">No reminders</li>
  </ul>

  <h3>Daily</h3>
  <ul id="daily_reminders">
    <%= render @daily_reminders %>
    <li class="empty-state">No daily reminders</li>
  </ul>
</section>
```

**`app/views/reminders/_reminder.html.erb`** (Rails uses the model name for
`render collection`):
```erb
<li id="<%= dom_id(reminder) %>">
  <% if reminder.timer? %>
    <div data-controller="countdown"
         data-countdown-fire-at-value="<%= reminder.fire_at.iso8601 %>">
      <span>
        Started <%= reminder.created_at.in_time_zone(reminder.user.timezone).strftime("%-I:%M %p") %>
        · <%= ((reminder.fire_at - reminder.created_at) / 60).round %> min timer
      </span>
      <span data-countdown-target="display"></span>
    </div>
  <% else %>
    <span>
      <%= reminder.fire_at.in_time_zone(reminder.user.timezone).strftime("%-I:%M %p") %>
      — <%= reminder.message %>
    </span>
  <% end %>
</li>
```

---

### Step 3 — Broadcast append: `CommandResponder#schedule_reminder`

After `ReminderJob.set(...).perform_later(reminder.id)`, add:
```ruby
target = case reminder.kind
         when "timer"          then "timers"
         when "daily_reminder" then "daily_reminders"
         else                       "reminders"
         end
Turbo::StreamsChannel.broadcast_append_to(
  reminder.user,
  target: target,
  partial: "reminders/reminder",
  locals: { reminder: reminder }
)
```

**`spec/services/command_responder_spec.rb`**
- After scheduling a timer: `broadcast_append_to` called with target `"timers"`
- After scheduling a reminder: target `"reminders"`
- After scheduling a daily reminder: target `"daily_reminders"`
- Broadcast is called with the correct partial and locals

---

### Step 4 — Broadcast remove + daily append: `ReminderJob`

After `reminder.delivered!`, add:
```ruby
Turbo::StreamsChannel.broadcast_remove_to(reminder.user, target: dom_id(reminder))
```

After the daily rescheduling `Reminder.create!`, add:
```ruby
Turbo::StreamsChannel.broadcast_append_to(
  new_reminder.user,
  target: "daily_reminders",
  partial: "reminders/reminder",
  locals: { reminder: new_reminder }
)
```

**`spec/jobs/reminder_job_spec.rb`**
- After delivery: `broadcast_remove_to` called with `dom_id(reminder)`
- Non-daily: no append broadcast for a new reminder
- Daily: `broadcast_append_to` called for the new occurrence with target
  `"daily_reminders"`

---

### Step 5 — Stimulus countdown controller

**`app/javascript/controllers/countdown_controller.js`**
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { fireAt: String }
  static targets = ["display"]

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const remaining = new Date(this.fireAtValue) - Date.now()
    if (remaining <= 0) {
      this.element.hidden = true
      clearInterval(this.timer)
      return
    }
    const totalSeconds = Math.floor(remaining / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    this.displayTarget.textContent =
      `${minutes}:${seconds.toString().padStart(2, "0")} remaining`
  }
}
```

Register in `app/javascript/controllers/index.js`:
```javascript
import CountdownController from "./countdown_controller"
application.register("countdown", CountdownController)
```

---

### Step 6 — CSS: empty state and panel layout

Add to the appropriate stylesheet:
```css
/* Hide empty-state placeholder when real items are present */
ul:has(li:not(.empty-state)) .empty-state {
  display: none;
}
```

Add basic panel layout styles for `.va-pending` (font size, spacing, section headings).

---

## Dependencies & Risks

- **`:has()` CSS selector**: Supported in all modern browsers (Chrome 105+, Safari 15.4+,
  Firefox 121+). Acceptable for a personal voice assistant.
- **Turbo Stream race at page load**: If a reminder fires between the index query and
  subscription activation, the stale row persists until the next reload. For timers the
  Stimulus auto-hide provides a fallback. Accepted risk given low probability.
- **Broadcast failures are silent**: Action Cable broadcast errors do not surface to the
  user. The panel will self-correct on the next page load.

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-02-24-pending-timers-reminders-display-brainstorm.md](../brainstorms/2026-02-24-pending-timers-reminders-display-brainstorm.md)
  Key decisions carried forward: inline rendering on existing page; live countdown via
  Stimulus `setInterval`; auto-hide at zero; CSS `:has()` for empty state.
- `app/jobs/reminder_job.rb` — existing broadcast pattern
- `app/services/command_responder.rb:38` — `schedule_reminder` (broadcast goes here)
- `app/views/voice_commands/index.html.erb` — existing Turbo Stream subscription
- `app/models/reminder.rb` — `kind` / `status` enums, `fire_at`, `created_at`
