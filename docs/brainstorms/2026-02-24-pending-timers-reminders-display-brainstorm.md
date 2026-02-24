---
date: 2026-02-24
topic: pending-timers-reminders-display
---

# Display Pending Timers and Reminders

## What We're Building

A live panel on the main voice assistant screen showing the user's pending timers and
reminders. Timers appear first with a live countdown, followed by a one-time reminders
section and a daily reminders subsection. The list updates automatically when a new
timer or reminder is spoken, and items disappear when they fire.

## Why This Approach

Inline rendering on `voice_commands/index.html.erb` (Option A) was chosen over a
separate Turbo Frame + RemindersController (Option B). The existing page already has a
Turbo Stream subscription via `<%= turbo_stream_from current_user %>`, so appending and
removing items on the same channel requires no new infrastructure. Option B adds a
controller, route, and view for what is essentially a read-only sidebar.

## Key Decisions

- **Placement**: Below the orb/status area on `voice_commands/index.html.erb`
- **Page load**: `VoiceCommandsController#index` queries `current_user.reminders.pending` and
  passes them to the view, split into timers and reminders
- **Live append**: When `VoiceCommandsController#create` schedules a timer or reminder,
  it broadcasts a Turbo Stream `append` to the appropriate section (`#timers` or
  `#reminders`)
- **Live remove**: When `ReminderJob` fires and marks a reminder delivered, it broadcasts
  a Turbo Stream `remove` for that item's DOM id (`reminder_<id>`)
- **Countdown**: A `countdown` Stimulus controller reads `data-countdown-fire-at-value`
  (ISO8601 timestamp), diffs against `Date.now()`, and updates a display element every
  second via `setInterval`; format is `M:SS` (e.g. "2:43 remaining")
- **At zero**: Stimulus auto-hides the timer element when the countdown reaches zero,
  without waiting for the Turbo Stream remove (which arrives shortly after as a no-op)
- **Timer row display**: "Started 3:12 PM · 5 min timer" + live "2:43 remaining"
  countdown
- **Reminder row display**: fire_at formatted time + message (e.g. "9:00 PM — take
  medication")
- **Sections**: Timers → One-time reminders → Daily reminders (separate subsection
  label)
- **Empty state**: Panel is always visible; sections show "No active timers" / "No
  reminders" placeholder text when empty, so layout stays stable as items appear/disappear
- **DOM ids**: `dom_id(reminder)` → `"reminder_123"` for Turbo Stream targeting

## Resolved Questions

- **Countdown or static?** → Live countdown via Stimulus `setInterval`
- **Real-time updates?** → Yes, via existing Turbo Stream channel
- **Daily reminders grouping?** → Separate subsection within the reminders section
- **At zero?** → Stimulus auto-hides the element; Turbo Stream remove is a no-op
- **Empty state?** → Panel always visible with placeholder text per section

## Open Questions

- None

## Next Steps

→ `/workflows:plan` for implementation details
