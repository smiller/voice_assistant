---
status: complete
priority: p3
issue_id: "034"
tags: [code-review, testing, quality]
---

# Add Direct next_in_list Test for Timer Kind

## Problem Statement

`Reminder#next_in_list` has thorough tests for `reminder` and `daily_reminder` kinds, but no test calls `next_in_list` directly on a `timer` reminder. The timer branch uses the non-daily code path (absolute `fire_at` ordering via SQL), which is exercised indirectly by the "does not return reminders of a different kind" test. However, there is no test that confirms `next_in_list` returns the correct timer when called on a timer reminder. With 98.87% mutation coverage the risk is low, but the gap is visible.

## Findings

- `spec/models/reminder_spec.rb`: `describe "#next_in_list"` has contexts for "for a reminder" and "for a daily_reminder" but no "for a timer"
- Rails reviewer finding #8: "There is no test for `next_in_list` called on a timer. Not a blocker given 98.87% mutation coverage, but worth noting."
- Timer reminders use the same `else` branch as regular reminders: `siblings.order(:fire_at).where("fire_at > ?", fire_at).first`

## Proposed Fix

Add a `context "for a timer"` block to `spec/models/reminder_spec.rb`:

```ruby
context "for a timer" do
  it "returns nil when no other timers are pending" do
    timer = create(:reminder, :timer, user: user, fire_at: 2.hours.from_now)
    expect(timer.next_in_list).to be_nil
  end

  it "returns the timer that fires next after it" do
    sooner = create(:reminder, :timer, user: user, fire_at: 1.hour.from_now)
    later  = create(:reminder, :timer, user: user, fire_at: 3.hours.from_now)
    expect(sooner.next_in_list).to eq(later)
  end

  it "does not return reminders of a different kind" do
    timer    = create(:reminder, :timer, user: user, fire_at: 1.hour.from_now)
    _regular = create(:reminder, user: user, fire_at: 2.hours.from_now)
    expect(timer.next_in_list).to be_nil
  end
end
```

## Acceptance Criteria

- [ ] At least two passing `next_in_list` tests for `timer` kind
- [ ] Timer tests cover: nil when no siblings, correct sibling returned, kind isolation
- [ ] Mutation coverage holds or improves

## Work Log

- 2026-02-24: Identified by kieran-rails-reviewer during code review (finding #8)
