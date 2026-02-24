# Voice Assistant

A multi-user, browser-based voice assistant built with Rails 8. Press and hold Space to speak a command; the audio is transcribed, interpreted, and answered via synthesized speech. Timers and reminders are scheduled server-side and delivered to the open browser tab through Action Cable.

Built with Claude Code and
- Every.to's [compound-engineering plugin](https://github.com/EveryInc/compound-engineering-plugin)
- Lada Kesseler's TDD skill from her [skill-factory](https://github.com/lexler/skill-factory)

## Stack

- **Ruby** 4.0.1 / **Rails** 8.1
- **Speech-to-text** — [Deepgram](https://deepgram.com) (REST pre-recorded API)
- **Text-to-speech** — [ElevenLabs](https://elevenlabs.io)
- **Frontend** — Hotwire (Turbo + Stimulus), importmap, Propshaft
- **Background jobs** — Solid Queue (Rails default)
- **Real-time delivery** — Action Cable → Turbo Streams
- **Auth** — `has_secure_password` + session cookie
- **Database** — PostgreSQL
- **Testing** — RSpec, FactoryBot, mutant

## Voice commands

| Say | Response |
|-----|----------|
| "what time is it" | Speaks the current time in your timezone |
| "when is sunset" | Speaks today's sunset time for your location |
| "set a timer for 5 minutes" | Confirms with "Timer set for 5 minutes"; speaks "Timer finished after 5 minutes" when it fires |
| "set a 9pm reminder to take medication" | Confirms; speaks "It's 9:00 PM. Reminder: take medication" at 9:00 PM in your timezone |
| "set a 9:30pm reminder to take medication" | Same, with minutes |
| "set a daily 7am reminder to write morning pages" | Confirms; speaks "It's 7:00 AM. Reminder: write morning pages" every day at 7:00 AM and reschedules automatically |
| _(anything else)_ | "Sorry, I didn't understand that" |

**Notes:**
- Number words are normalised before matching — "five minutes" and "5 minutes" both work.
- If a reminder time has already passed today it is automatically scheduled for tomorrow, e.g. "Reminder set for 7:00 AM tomorrow to take medication".
- Alerts are silently dropped if the browser tab is closed when the job fires.

## Setup

### Prerequisites

- Ruby 4.0.1
- PostgreSQL
- A [Deepgram](https://deepgram.com) API key
- An [ElevenLabs](https://elevenlabs.io) API key and voice ID

### Environment variables

Copy `.env.example` to `.env` and fill in your keys:

```
DEEPGRAM_API_KEY=your_key_here
ELEVENLABS_API_KEY=your_key_here
ELEVENLABS_VOICE_ID=your_voice_id_here   # used as the default for all users
```

### Database

```bash
bin/rails db:create db:migrate
```

### Create a user

Registration is invite-only. Create accounts in the Rails console:

```ruby
User.create!(email: "you@example.com", password: "secure_password")
# timezone defaults to "Eastern Time (US & Canada)"; override with timezone: "Pacific Time (US & Canada)"
# lat/lng are captured automatically from the browser on first login
```

### Run the app

```bash
bin/rails server
```

Background jobs run in-process in development via Solid Queue. In production, run a separate worker:

```bash
bin/jobs
```

## Testing

```bash
bundle exec rspec                         # full suite
bundle exec rspec spec/models/            # scoped
bundle exec mutant run --use rspec 'ClassName'  # mutation testing
bundle exec rubocop                       # lint
```

## Settings

Each user can update their ElevenLabs voice ID, location (lat/lng), and timezone at `/settings`.

Latitude and longitude are auto-populated from the browser's Geolocation API on first login if not already set.
