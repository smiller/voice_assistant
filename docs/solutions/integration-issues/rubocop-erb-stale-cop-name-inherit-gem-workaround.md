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
  - "bundle exec rubocop only inspects ERB files — Ruby files silently excluded"
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

**Silent Ruby file exclusion with `plugins:` + bare `Include:`:**
```
$ bundle exec rubocop --list-target-files
app/views/layouts/application.html.erb
app/views/voice_commands/index.html.erb
... (only ERB files — all .rb files missing)
```

## Root Cause

Three separate issues compound here:

1. **Stale cop name**: `rubocop-erb` 0.7.0's bundled `config/default.yml`
   references `Layout/LeadingEmptyLine` (singular), renamed to
   `Layout/LeadingEmptyLines` (plural) in a newer RuboCop release. Loading
   that config via `inherit_gem` causes RuboCop to abort at startup.

2. **Deprecated require API**: Using `require: rubocop-erb` bypasses the
   stale config and works, but rubocop-erb has migrated to the RuboCop
   plugin API, so `require:` is deprecated in favour of `plugins:`.

3. **Include replaces rather than merges**: When you add `Include:` under
   `AllCops` in your own `.rubocop.yml`, it *replaces* the default Ruby file
   patterns inherited from parent configs rather than appending to them.
   Adding `"**/*.erb"` without `inherit_mode: merge` silently drops all
   `**/*.rb` patterns, leaving only ERB files in the target list.

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

```yaml
# ❌ plugins + bare Include — silently drops Ruby files from target list
plugins:
  - rubocop-erb
AllCops:
  Include:
    - "**/*.erb"   # replaces inherited Ruby patterns; only ERB files inspected
```

## Solution

Use `plugins:`, add `"**/*.erb"` to `AllCops/Include`, and add
`inherit_mode: merge: Include` so the ERB pattern is appended to the
inherited Ruby patterns rather than replacing them:

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

# merge (not replace) Include/Exclude arrays from inherited configs
inherit_mode:
  merge:
    - Include
    - Exclude

inherit_gem:
  rubocop-rails-omakase: rubocop.yml

AllCops:
  NewCops: enable
  TargetRubyVersion: 4.0
  Include:
    - "**/*.erb"          # appended to inherited Ruby patterns via inherit_mode
  Exclude:
    - "db/schema.rb"
    - "db/migrate/*.rb"
    - "bin/**/*"
```

## Verification

```bash
# Check the full target file list — should include both .rb and .erb files
bundle exec rubocop --list-target-files

# Run the full suite — file count should match all Ruby + ERB files
bundle exec rubocop
# => XX files inspected, no offenses detected  (not just 10 ERB files)
```

## Prevention

- **Before adding any RuboCop extension**, check whether it ships a
  `config/default.yml` with cop names that match your RuboCop version.
  If unsure, prefer `plugins:` + explicit `Include:` patterns over
  `inherit_gem:` — this bypasses any stale config the gem bundles.
- **Always add `inherit_mode: merge: Include` when extending `AllCops/Include`.**
  Without it, any `Include:` you add replaces the inherited patterns from
  parent configs, silently dropping all Ruby files from the target list.
  Verify with `bundle exec rubocop --list-target-files`.
- **When rubocop-erb releases a fix** (updating `default.yml` to use
  `Layout/LeadingEmptyLines`), `inherit_gem: rubocop-erb: config/default.yml`
  will work again and the `plugins:` + manual `Include:` workaround can be
  simplified.
