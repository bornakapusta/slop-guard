---
status: complete
priority: p1
issue_id: "004"
tags: [code-review, architecture, agent-native]
dependencies: []
---

# Review orchestration lives only in bin/review; no library entry point for a GitHub bot

## Problem Statement

bin/review reads expectations, builds GitSource, builds Snapshot with the profile, decides the rules variant via `repository: !options.key?(:rules)`, loads .env, creates the output directory, wires Budget, JevClient and Evaluator, patches `report['source']` in afterwards, writes report.json and picks the exit code. None of this is callable from lib/. A GitHub App or any agent would copy about 35 lines including the subtle rule-profile decision and the metadata merge, and drift over time. Evaluator emits a report without provenance; inspect mode re-assembles it by hand.

## Findings

- `bin/review:32-69` contains the full composition; `bin/review:64` mutates the report after evaluation.
- `bin/review:49-55` re-assembles inspect output by hand from snapshot, source and rules.
- `lib/slop_guard/evaluator.rb:41-43` report has no `source` key unless the CLI adds it.
- bin/review coverage is 0% (subprocess-only via `spec/slop_guard/cli_spec.rb`), so this logic is only tested end-to-end.
- Three bin scripts rescue three different exception sets (`bin/review:70-75`, `bin/evaluate:69`, `bin/analyze-evaluation`).

## Proposed Solutions

### Option 1: SlopGuard::Review facade

**Approach:** Add `SlopGuard::Review.new(snapshot:, rules:, client:)` (or `SlopGuard.review(...)`) returning a complete report including `source` metadata taken from the input hash. Add a `SlopGuard::CLI` that parses args and calls it. bin/review becomes ~10 lines. cli_spec can run in-process.

**Pros:**
- One place for composition
- Report complete regardless of caller
- CLI becomes unit-testable and coverage becomes real

**Cons:**
- Moderate refactor touching all three bins

**Effort:** Medium (half a day)

**Risk:** Low

---

### Option 2: Move provenance into Evaluator only

**Approach:** Have Snapshot carry `source` metadata and Evaluator emit it; leave composition in bin/review.

**Pros:**
- Smallest change fixing report completeness

**Cons:**
- Bot still copies the wiring

**Effort:** Small (1-2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `bin/review`
- `bin/evaluate`
- `lib/slop_guard/evaluator.rb:41-43`
- `lib/slop_guard/snapshot.rb`
- `spec/slop_guard/cli_spec.rb`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] A report produced via the library includes `source` metadata without CLI post-processing
- [ ] bin/review contains only option parsing and printing
- [ ] cli_spec exercises the CLI in-process with a stubbed client
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
- `SlopGuard::CLI` (lib/slop_guard/cli.rb) owns composition; `Evaluator` emits `source` and `report_version`; bin/review is three lines; cli_spec runs in-process.
