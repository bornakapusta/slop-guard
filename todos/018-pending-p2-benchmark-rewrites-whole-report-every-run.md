---
status: pending
priority: p2
issue_id: "018"
tags: [code-review, performance]
dependencies: [013]
---

# Benchmark mode rewrites the whole growing report after every review

## Problem Statement

EvalRunner#run pretty-prints and renames the full result after each case review. At 100 repetitions times 16 cases that is 1,600 writes of a file growing to tens of MiB, roughly 20-30 GB of cumulative JSON generation, with the whole result held in memory. Fine for 3 repetitions; hostile for the 100-repetition benchmark the code explicitly allows.

## Findings

- `lib/slop_guard/eval_runner.rb:99` `save` per run; `eval_runner.rb:168-171` writes and renames the full report.
- `eval_runner.rb:67` allows 1..100 repetitions in benchmark mode.

## Proposed Solutions

### Option 1: Append runs.jsonl, write report at end

**Approach:** Append each run as one JSON line to `runs.jsonl` (atomic per line), write `report.json` once at the end or every N runs, and rebuild from runs.jsonl on a stopped benchmark.

**Pros:**
- Linear IO
- Partial progress still recoverable

**Cons:**
- analyze-evaluation may need to accept runs.jsonl

**Effort:** Small-Medium (2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/eval_runner.rb:80-100,166-172`
- `bin/analyze-evaluation`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Per-run write cost is constant
- [ ] A benchmark stopped mid-way leaves recoverable run records
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


