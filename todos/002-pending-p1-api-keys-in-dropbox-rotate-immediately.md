---
status: pending
priority: p1
issue_id: "002"
tags: [code-review, security]
---

# Rotate API Keys — Live Secrets Synced to Dropbox

## Problem Statement
Both `DEEPGRAM_API_KEY` and `ELEVENLABS_API_KEY` in `.env` and `config/master.key` are live credentials stored inside a Dropbox-synced directory (`/Users/seanmiller/Library/CloudStorage/Dropbox/code/`). These files are actively synced to Dropbox's cloud servers and accessible to anyone with read access to this Dropbox account.

## Findings
- `.env` contains live `DEEPGRAM_API_KEY`, `ELEVENLABS_API_KEY`, and `ELEVENLABS_VOICE_ID`
- `config/master.key` decrypts `credentials.yml.enc`
- Both are excluded from git (`.gitignore`) but are synced to Dropbox
- `.gitignore` does NOT protect against Dropbox sync

## Proposed Solutions

### Option A: Rotate keys + add .dropboxignore (Recommended)
1. Rotate both API keys via Deepgram and ElevenLabs dashboards immediately
2. Add `.dropboxignore` file to project root excluding `.env` and `config/master.key`
3. Update `.env` with new keys
- Effort: Small | Risk: Low (rotation is routine)

### Option B: Move project out of Dropbox
Move the entire project to a non-synced directory (e.g., `~/code/`)
- Pros: Permanent fix for all secrets
- Cons: Disrupts workflow if Dropbox is used for backup
- Effort: Small

## Acceptance Criteria
- [ ] Deepgram API key rotated
- [ ] ElevenLabs API key rotated
- [ ] `.dropboxignore` or project relocation prevents future sync of secrets
- [ ] New keys work and app is functional

## Work Log
- 2026-02-23: Identified by security-sentinel during code review
