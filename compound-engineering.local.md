---
review_agents:
  - kieran-rails-reviewer
  - security-sentinel
  - performance-oracle
  - architecture-strategist
  - code-simplicity-reviewer
---

## Project Context

Ruby on Rails 8 voice assistant application. Stack: Rails + Hotwire (Turbo/Stimulus) + PostgreSQL + RSpec + FactoryBot + mutant-rspec + RuboCop.

Key conventions:
- Strict TDD (no implementation without a failing test)
- Thin controllers, business logic in service objects/POROs
- Turbo Streams for real-time updates (broadcast_append_to, broadcast_replace_to)
- Active Job for background work
- Conventional Commits commit style
