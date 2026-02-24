---
title: "CommandParser: Four Spoken-Time Parsing Bugs from Deepgram Transcription"
date: 2026-02-24
category: logic-errors
tags:
  - command-parser
  - speech-to-text
  - deepgram
  - word-to-number
  - regex
  - tdd
symptoms:
  - "Space-separated spoken times like 'six thirty pm' return :unknown intent"
  - "Compound minute words like 'forty nine' resolve to 40 instead of 49"
  - "Words like 'fifty', 'sixteen'–'nineteen' cause :unknown or wrong minute values"
  - "'seven zero one pm' fails to parse; 'zero' treated as unrecognized token"
components:
  - CommandParser
  - WORD_TO_NUMBER dictionary
  - normalize_numbers pipeline
severity: medium
resolved: true
resolution_time: "~2 hours (four sequential TDD cycles)"
---

# CommandParser: Four Spoken-Time Parsing Bugs from Deepgram Transcription

## Root Cause Summary

The `CommandParser` service failed to handle naturalistic spoken-time transcriptions produced
by Deepgram. Deepgram transcribes times as individual English words with no inherent grouping
("six forty nine pm", not "6:49 pm"). The `normalize_numbers` method converted individual
words to digits but left multi-token numeric sequences unmerged. The `WORD_TO_NUMBER`
dictionary was also incomplete, causing many common minute values to pass through unnormalized
and fall through to `:unknown`.

## Bug 1: Space-Separated Spoken Times Not Matched

**Symptom:** `parse("set a six thirty pm reminder to test reminders")` returned `:unknown`.

**Cause:** After word-to-number normalization, "six thirty" became "6 30" — two space-separated
digit tokens. The regex separator `[: ]` is capable of matching a space between hour and
minute, but the capture was failing because the normalization pipeline was not producing clean
output in all cases, or the minute capture group wasn't being extracted correctly when a space
(rather than a colon) was the separator.

**Fix:** Confirmed the regex `(\d{1,2})(?:[: ](\d{1,2}))?` handles both colon-delimited
("6:30") and space-delimited ("6 30") forms; ensured normalization produced clean single-space
separators so the space-separated form matched reliably.

## Bug 2: Compound Minute Words ("forty nine" → 40 instead of 49)

**Symptom:** `parse("set a six forty nine pm reminder to check dinner")` produced `minute: 40`.

**Cause:** `normalize_numbers` replaced each word independently: "forty" → "40", "nine" → "9",
yielding "6 40 9 pm". The existing oh-collapser `\b0 ([1-9])\b` only handled "0 N" patterns.
There was no rule to merge a tens token followed by a ones token ("40 9") into their sum (49).

**Fix:** Added a third pass to `normalize_numbers`:

```ruby
oh_collapsed.gsub(/\b([1-5]0) ([1-9])\b/) { ($1.to_i + $2.to_i).to_s }
```

This matches any tens value (10–50) immediately followed by a ones digit (1–9) and replaces
both with their integer sum.

## Bug 3: Incomplete Word-to-Number Dictionary

**Symptom:** "six fifty pm", "six sixteen pm", "six seventeen pm" etc. returned wrong minute
values or `:unknown`.

**Cause:** `WORD_TO_NUMBER` only covered up to "twenty" plus isolated entries for "thirty" and
"forty-five". Missing: "thirteen"–"nineteen", "forty", "fifty", "sixty".

**Fix:** Added all missing entries to cover the full range needed for minutes 0–59:

```ruby
"thirteen" => 13, "fourteen" => 14, "fifteen" => 15,
"sixteen"  => 16, "seventeen" => 17, "eighteen" => 18, "nineteen" => 19,
"forty"    => 40, "fifty"     => 50, "sixty"    => 60
```

## Bug 4: "zero" Not Mapped to 0

**Symptom:** `parse("set a seven zero one pm reminder")` failed to parse correctly.

**Cause:** "zero" was absent from `WORD_TO_NUMBER`. The string "seven zero one" normalized to
"7 zero 1" — the word "zero" passed through unchanged, breaking the oh-collapser (`\b0 ([1-9])\b`
requires a digit zero, not the word) and the time regex downstream.

**Fix:** Added `"zero" => 0` alongside `"oh" => 0`. Deepgram uses both interchangeably for
leading-zero minutes ("seven oh one" and "seven zero one" both mean 7:01).

## Final normalize_numbers Pipeline

```ruby
def normalize_numbers(text)
  # Pass 1: replace every known English word with its digit string
  words_replaced = WORD_TO_NUMBER.reduce(text) do |t, (word, digit)|
    t.gsub(/\b#{word}\b/i, digit.to_s)
  end

  # Pass 2: collapse "0 N" (spoken "oh one", "zero three") into "0N"
  oh_collapsed = words_replaced.gsub(/\b0 ([1-9])\b/) { "0#{$1}" }

  # Pass 3: merge tens+ones pairs ("40 9" -> "49", "20 5" -> "25")
  oh_collapsed.gsub(/\b([1-5]0) ([1-9])\b/) { ($1.to_i + $2.to_i).to_s }
end
```

The three passes are ordered deliberately: word substitution must complete before
pattern-based collapsing, and oh-collapsing must complete before tens+ones merging.

## Deepgram Transcription Patterns Reference

Deepgram outputs times as individual English words. Common patterns:

| Spoken input | Deepgram output | After normalize_numbers |
|---|---|---|
| "six thirty" | `"six thirty"` | `"6 30"` |
| "six forty nine" | `"six forty nine"` | `"6 49"` |
| "six oh one" | `"six oh one"` | `"6 01"` |
| "six zero one" | `"six zero one"` | `"6 01"` |
| "six five" | `"six five"` | `"6 5"` → matched as 6:05 |
| "six sixteen" | `"six sixteen"` | `"6 16"` |
| "six fifty" | `"six fifty"` | `"6 50"` |

## Prevention Strategies

**Define the full word-to-number dictionary up front.** The English words for numbers 0–60 are
a finite, known set. Any dictionary that doesn't cover it completely on day one is a latent bug.
Add a comment marking the intended range so reviewers can spot gaps immediately.

**Front-load input enumeration before writing tests.** Collect or simulate actual Deepgram
output for the full range of spoken time forms before implementing the parser. The iterative
bug-per-cycle pattern in this session could be compressed into a single comprehensive test pass.

**Two-word tokens require explicit aggregation logic.** Parsers naturally handle single-token
lookups and break silently on multi-token representations of a single value ("forty nine").
Whenever a concept can be expressed as multiple adjacent tokens, the parser must explicitly
model their combination.

**Document ambiguous input forms with a policy.** "Six five" could mean 6:05 or 6:50. The
parser resolves it one way; that choice must be named, commented, and tested — otherwise it
becomes an invisible user-facing bug.

## Test Case Checklist (for future time-parsing changes)

### WORD_TO_NUMBER dictionary coverage
- [ ] All units 0–9 mapped, including "oh" and "zero" for 0
- [ ] Teens 11–19 all mapped
- [ ] All tens 10–60 mapped
- [ ] "forty-five" as a hyphenated entry (Deepgram sometimes produces this)

### Compound minute parsing
- [ ] `"forty nine"` → 49 (tens + ones)
- [ ] `"fifty nine"` → 59
- [ ] `"twenty one"` → 21
- [ ] Single tens alone: `"forty"` → 40

### Leading-zero patterns
- [ ] `"oh five"` → minute 5
- [ ] `"zero five"` → minute 5
- [ ] `"oh one"` → minute 1

### 12-hour boundary cases
- [ ] `"twelve am"` → hour 0
- [ ] `"twelve pm"` → hour 12
- [ ] `"twelve thirty am"` → hour 0, minute 30
- [ ] `"twelve thirty pm"` → hour 12, minute 30

### Space-separated input
- [ ] `"six thirty"` parses correctly
- [ ] `"six oh five"` parses correctly
- [ ] `"six forty nine"` parses correctly

## Generalizable Lessons

1. **Spoken language is not a subset of written language — model it separately.** Any parser
   ingesting speech-to-text output must treat Deepgram's transcription format as its own domain
   with its own rules. Do not write against an idealized input and add edge cases reactively.

2. **Finite vocabularies demand complete coverage, not iterative discovery.** If the set of
   possible input tokens is bounded and known (number words, day names, currency words), define
   it completely on day one.

3. **Multi-pass normalization pipelines must be ordered deliberately.** Each pass must operate
   on the output of the previous one. Word→digit substitution must complete before structural
   collapsing (oh-prefix, tens+ones). Attempting both in a single pass produces incorrect
   results for compound inputs.

4. **TDD feedback loops compress when input enumeration is front-loaded.** The four sequential
   fix cycles here were TDD working correctly, but each cycle could have been avoided with a
   more complete initial test suite. Precede TDD with domain analysis so the initial tests cover
   the full input space.
