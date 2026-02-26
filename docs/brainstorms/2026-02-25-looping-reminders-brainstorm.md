---
date: 2026-02-25
topic: looping-reminders
---

# Looping Reminders

## What We're Building

A new category of schedulable item — the **looping reminder** — that fires every N minutes
indefinitely until stopped by a specific voice stop phrase. Looping reminders are numbered,
reusable (never deleted), and can be given voice aliases. They live between Timers and
Reminders on the main screen.

## Core Behavior

**Creation:** `"set a looping reminder for 5 minutes saying 'have you done the dishes?' until I say 'doing the dishes'"`

- Stores: interval (minutes), prompt message, stop phrase
- Assigns the next sequential number (1, 2, 3…) per user
- Immediately transitions to **active** state and schedules the first fire for N minutes from now
- Assistant confirms: `"Created looping reminder 1, will ask 'have you done the dishes?' every 5 minutes until you reply 'doing the dishes'"`

**Activation:** `"run loop 1"` or `"run looping reminder 1"`

- Transitions to **active** state
- Fires prompt audio after N minutes, then every N minutes
- If already active: no action taken, assistant says `"Loop 1 already active"`

**Stop:** User speaks the loop's registered stop phrase (e.g., `"doing the dishes"`)

- Parser scans active loops for a matching stop phrase
- Transitions loop back to **idle** state
- Assistant says: `"Excellent. Stopping looping reminder 1"`

**Stop phrase uniqueness:** Stop phrases must be unique across a user's loops.
If a creation command uses an already-registered stop phrase, the assistant says
`"Stop phrase already in use. Enter a different stop phrase?"` and enters a
**multi-turn waiting state** — the next voice input is captured as the replacement
stop phrase rather than parsed as a regular command.

**Aliasing:** `"alias 'run loop 1' as 'remember the dishes'"`

- Going forward, saying `"remember the dishes"` is equivalent to `"run loop 1"`
- Aliases are displayed on-screen alongside the loop

**Scheduling model:** Reuses the existing chained-job pattern from daily reminders.
Each `LoopingReminderJob` delivery, if the loop is still active, schedules the next
job for `fired_at + interval_minutes`. If the loop was stopped in between, the job
exits early.

## Why This Approach

### New model (`LoopingReminder`) vs. extending `Reminder` with a new kind

Looping reminders have enough distinct columns (interval_minutes, stop_phrase, number,
active boolean) and distinct lifecycle (idle → active → idle, never deleted) that
adding them as a new `kind` on the existing `Reminder` model would require many
nullable columns and complicate existing validations.

**Decision: new `LoopingReminder` model.** Keeps the existing `Reminder` clean.

### Alias storage

Aliases are essentially user-defined phrases that resolve to "run loop N". They could
live as a column on `LoopingReminder` (single alias) or as a separate `CommandAlias`
model (multiple aliases per loop, extensible to other command types).

**Decision: `CommandAlias` model** with `phrase` and `looping_reminder_id`. Allows
multiple aliases per loop and leaves room for aliasing other command types later.

### Multi-turn state

When waiting for a replacement stop phrase, we need to persist state between requests.
Options: User column, Rails.cache, or a dedicated table.

**Decision: `PendingInteraction` model** (user_id, kind, context jsonb). Clean,
queryable, survives server restarts. Kind `"stop_phrase_replacement"` with context
`{ looping_reminder_id: N }`.

## Key Decisions

- **New `LoopingReminder` model** rather than extending `Reminder` with a new kind
- **`CommandAlias` model** for voice aliases (phrase → looping_reminder_id)
- **`PendingInteraction` model** for multi-turn stop-phrase replacement flow
- **Stop phrases are unique per user** — enforced at creation time
- **First fire after N minutes** (not immediately on activation)
- **Chained-job scheduling** — each job schedules the next, same as daily reminders
- **Stop confirmation:** `"Excellent. Stopping looping reminder N"`
- **Never deleted** — loops accumulate per user; numbers are permanent
- **Display position:** between Timers and Reminders (`<ul id="looping_reminders">`)
- **Display format (idle):** `1 · remind every 5 min 'have you done the dishes?' until 'doing the dishes'`
- **Display format (active):** `1 · active · remind every 5 min 'have you done the dishes?' until 'doing the dishes'`
- **Display format with alias:** `1 (remember the dishes) · active · remind every 5 min …`
- **Multiple aliases per loop** supported; displayed comma-separated: `1 (remember the dishes, do the washing) · …`
- **Alias collision:** same pattern as stop-phrase collision — refuse with prompt, enter multi-turn waiting state for replacement phrase
- **Server restart kills active loops** — re-enqueue-on-boot is a separate future brainstorm

## New Intents Required

| Intent | Example phrase |
|---|---|
| `:create_loop` | `"set a looping reminder for 5 minutes saying '...' until I say '...'"` |
| `:run_loop` | `"run loop 1"` / `"run looping reminder 1"` |
| `:alias_loop` | `"alias 'run loop 1' as 'remember the dishes'"` |
| Stop phrase match | Scanned against `LoopingReminder.where(active: true)` before normal parsing |

Alias phrases (e.g., `"remember the dishes"`) are looked up from `CommandAlias` before
normal parsing and translated to their equivalent `:run_loop` intent.

## Future Considerations (out of scope this cycle)

- **Loop deletion from screen** — looping reminders should eventually be deletable like daily reminders
- **Alias deletion** — voice command to remove an alias (e.g., `"remove alias 'remember the dishes'"`)
- **Server restart resilience** — a dedicated brainstorm to decide what happens to active loops (and other scheduled work) on server restart; for now, restart silently kills active loops

## Open Questions

_None — all resolved during brainstorm._

## Resolved Questions

- **Stop phrase collision:** Refuse with prompt, enter multi-turn waiting state for
  replacement. Handled via `PendingInteraction`.
- **First fire timing:** Creation immediately activates the loop; first audio fires N minutes later (not at minute 0).
- **Stop confirmation:** `"Excellent. Stopping looping reminder N"`.
- **Multi-turn flow:** Required in v1, not deferred.
- **Multiple aliases:** A loop can have more than one alias; displayed comma-separated in parens.
- **Alias collision:** Refused with prompt + multi-turn waiting state, same pattern as stop-phrase collision.
- **Loop deletion:** Deletable (like daily reminders), but deferred to a future cycle.
- **Alias deletion:** Voice command to remove an alias, deferred to a future cycle.
- **Server restart:** Kills active loops; server-restart resilience is a separate future brainstorm.
