---
status: complete
priority: p2
issue_id: "015"
tags: [code-review, quality]
dependencies: []
---

# Broad `rescue NoMethodError` in validators masks programmer bugs as bad input

## Problem Statement

Five validators rescue NoMethodError alongside KeyError/TypeError and re-raise a generic "invalid input" message. A typo or nil bug inside the validator is reported as "Invalid dataset manifest or labels" or "Jev returned a malformed response", hiding the real defect. The unknown-id crash in todo 006 is an example of a nil path that would be misreported once inside such a block.

## Findings

- `dataset.rb:112`, `rules.rb:24`, `evaluation_analysis.rb:14`, `jev_client.rb:122`, `script/evaluation_summary.rb:127`.

## Proposed Solutions

### Option 1: Explicit shape checks

**Approach:** Drop NoMethodError from the rescue lists and add explicit `is_a?` checks (or parse with `symbolize_names: true` and use `case/in` pattern matching in JevClient#validate, which is the clearest fit for the provider contract).

**Pros:**
- Bugs surface as bugs
- Pattern matching documents the contract

**Cons:**
- A few more lines per validator

**Effort:** Small-Medium (2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/dataset.rb:112`
- `lib/slop_guard/rules.rb:24`
- `lib/slop_guard/evaluation_analysis.rb:14`
- `lib/slop_guard/jev_client.rb:96-124`
- `script/evaluation_summary.rb:127`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No `rescue NoMethodError` in lib/ or script/
- [ ] Malformed provider response specs still pass
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



### 2026-09-20 - Fixed

**By:** Claude Code (Phases 2-5, branch `refactor/review-phases-2-6`)

**Actions:**
- No `rescue NoMethodError` remains in lib/; validators check shapes with is_a? before fetching. Ruby hash patterns need symbol keys, so JevClient#validate uses explicit checks.
