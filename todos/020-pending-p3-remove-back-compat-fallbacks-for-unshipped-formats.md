---
status: pending
priority: p3
issue_id: "020"
tags: [code-review, simplification]
dependencies: [009]
---

# Remove back-compat fallbacks for report formats that never shipped

## Problem Statement

EvaluationAnalysis falls back to `legacy-#{batch}` fingerprints when `question_fingerprints` is absent, bin/analyze-evaluation falls back to the manifest when `case_ids` is absent, and the summary guards on `case_ids`. The runner has always written both fields, tmp/ is ignored and eval/baselines are inputs not reports, so no historical report exists in the repo. docs/evaluation-benchmark.md documents the legacy key.

## Findings

- `evaluation_analysis.rb:116-120`, `bin/analyze-evaluation:21`, `script/evaluation_summary.rb:47`, `docs/evaluation-benchmark.md:49`.
- Root cause is `evaluator.rb:54` `||=`; eager initialisation (todo 009) removes the need.

## Proposed Solutions

### Option 1: Require both fields

**Approach:** Initialise `question_fingerprints` eagerly, require both fields in validators, delete the fallbacks and the legacy paragraph. Verify no offline reports live outside the repo first.

**Pros:**
- ~20 lines removed
- One report shape

**Cons:**
- Any stray old report becomes unreadable

**Effort:** Small (1 hour)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/evaluation_analysis.rb:116-120`
- `bin/analyze-evaluation:21`
- `script/evaluation_summary.rb:47`
- `docs/evaluation-benchmark.md`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No `legacy-` branch remains
- [ ] Validators reject reports missing `question_fingerprints` or `case_ids`
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



## Notes

**Correction (2026-09-20, spec-flow analysis):** the premise "no historical report exists in the repo" is false. All `docs/verification/*.json` reports (evaluation-benchmark, first-live-development, fixture-runs, threshold-calibration) lack both `question_fingerprints` and `case_ids`, and docs point `bin/analyze-evaluation` at them. Either keep a documented fallback for committed historical reports or mark them historical and stop referencing them from analysis commands. Do not simply require the fields.
