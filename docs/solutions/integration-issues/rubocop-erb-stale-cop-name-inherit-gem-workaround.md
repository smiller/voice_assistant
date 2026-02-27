---
title: "rubocop-erb: stale cop name prevents inherit_gem; use plugins API instead"
problem_type: integration-issues
affected_components:
  - .rubocop.yml
  - rubocop-erb gem
  - ERB view linting
symptoms:
  - "unrecognized cop or department Layout/LeadingEmptyLine found in rubocop-erb-0.7.0/config/default.yml"
  - "rubocop-erb extension supports plugin, specify `plugins: rubocop-erb` instead of `require: rubocop-erb`"
tags:
  - rubocop
  - rubocop-erb
  - configuration
  - erb-linting
date: 2026-02-26
versions:
  rubocop-erb: "0.7.0"
  ruby: "4.0.1"
  rails: "8.1.2"
---

# rubocop-erb: stale cop name prevents inherit_gem; use plugins API instead

## Symptoms

Two failure modes appear when wiring up rubocop-erb, depending on which
`.rubocop.yml` approach is used:

**Error (config load failure) with `inherit_gem`:**
```
Error: unrecognized cop or department Layout/LeadingEmptyLine found in
/path/to/rubocop-erb-0.7.0/config/default.yml
Did you mean `Layout/LeadingEmptyLines`, `Layout/TrailingEmptyLines`?
```

**Deprecation warning with `require`:**
```
rubocop-erb extension supports plugin, specify `plugins: rubocop-erb`
instead of `require: rubocop-erb` in .rubocop.yml.
```

## Root Cause

`rubocop-erb` 0.7.0's bundled `config/default.yml` references the cop
`Layout/LeadingEmptyLine` (singular), which was renamed to
`Layout/LeadingEmptyLines` (plural) in a newer RuboCop release. Loading
that config via `inherit_gem` causes RuboCop to abort at startup because
the cop name no longer exists.

Using `require: rubocop-erb` bypasses the stale config file and works, but
rubocop-erb has since migrated to the RuboCop plugin API, so `require:` is
deprecated in favour of `plugins:`.

## What Doesn't Work

```yaml
# ❌ inherit_gem — crashes: references stale cop Layout/LeadingEmptyLine
inherit_gem:
  rubocop-erb: config/default.yml
```

```yaml
# ❌ require — works but prints deprecation warning on every run
require:
  - rubocop-erb
```

## Solution

Use the `plugins:` API and manually add `"**/*.erb"` to `AllCops/Include`
(since we skip `inherit_gem`, the gem's Include pattern is not loaded):

**Gemfile:**
```ruby
group :development, :test do
  gem "rubocop-rails-omakase", require: false
  gem "rubocop-erb", require: false   # require: false — RuboCop loads it via plugins:
end
```

**.rubocop.yml:**
```yaml
# rubocop-erb 0.7.0 config/default.yml references the stale cop
# Layout/LeadingEmptyLine (renamed to LeadingEmptyLines), so we skip
# inherit_gem and use the plugin API directly. Track fix at:
# https://github.com/rubocop/rubocop-erb
plugins:
  - rubocop-erb

inherit_gem:
  rubocop-rails-omakase: rubocop.yml

AllCops:
  NewCops: enable
  TargetRubyVersion: 4.0
  Include:
    - "**/*.erb"          # must be explicit — not loaded from gem's default.yml
  Exclude:
    - "db/schema.rb"
    - "db/migrate/*.rb"
    - "bin/**/*"
```

## Verification

```bash
# No errors, no warnings — clean config load
bundle exec rubocop app/views/

# Confirm ERB files are being inspected
bundle exec rubocop --debug 2>&1 | grep "\.erb"
```

## Prevention

- **Before adding any RuboCop extension**, check whether it ships a
  `config/default.yml` with cop names that match your RuboCop version.
  If unsure, prefer `plugins:` + explicit `Include:` patterns over
  `inherit_gem:` — this bypasses any stale config the gem bundles.
- **When rubocop-erb releases a fix** (updating `default.yml` to use
  `Layout/LeadingEmptyLines`), `inherit_gem: rubocop-erb: config/default.yml`
  will work again and the `plugins:` + manual `Include:` workaround can be
  simplified.
