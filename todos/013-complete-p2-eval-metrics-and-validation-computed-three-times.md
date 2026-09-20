---
status: complete
priority: p2
issue_id: "013"
tags: [code-review, simplification, quality]
dependencies: [012]
---

# Evaluation metrics and validation are computed three times across runner, analysis and summary

## Problem Statement

EvalRunner#run builds totals, per-rule precision/recall and `probability_ranges`; EvaluationAnalysis recomputes per-rule confusion, precision/recall and `probability_variance` over the same runs; script/evaluation_summary.rb has a third `validate!`, `complete?`, cost sums and pair checks, then instantiates EvaluationAnalysis anyway. `probability_ranges` is read by nothing outside the runner. `ratio` and non-negative checks are duplicated verbatim. These are also the worst Metrics offenders (EvalRunner#run ABC 133, EvaluationAnalysis#validate! CC 56).

## Findings

- `lib/slop_guard/eval_runner.rb:106-126,150-164` vs `lib/slop_guard/evaluation_analysis.rb:74-131,152` vs `script/evaluation_summary.rb:8-131`.
- Identical pair-check message at `evaluation_analysis.rb:186-190` and `script/evaluation_summary.rb:87-91`.
- `nonnegative` checks: `evaluation_analysis.rb:248`, `script/evaluation_summary.rb:92,105,110,151`.
- Only `probability_variance` has spec coverage; `probability_ranges` has none.

## Proposed Solutions

### Option 1: Runner records, Analysis computes, Summary delegates

**Approach:** EvalRunner records runs plus passed/completed/seconds and calls `EvaluationAnalysis.new(result, case_ids:).to_h` for metrics (keep `metrics.by_rule` and `outcome_flips` keys consumed by bin/evaluate and the CI spec). Delete `probability_ranges`. EvaluationSummary constructs an EvaluationAnalysis and delegates validation, keeping only CI status and ledger logic. Move `ratio`/`nonnegative!` to one small helper. Split `EvalRunner#run` into prepare / review_case / finalize.

**Pros:**
- ~100-150 lines removed
- One definition of every metric
- Fixes the two worst Metrics offenders

**Cons:**
- Report keys consumed by docs/verification and CI spec must be preserved

**Effort:** Medium (half a day)

**Risk:** Medium

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/eval_runner.rb:62-172`
- `lib/slop_guard/evaluation_analysis.rb`
- `script/evaluation_summary.rb`
- `spec/ci/evaluation_summary_spec.rb`
- `spec/eval/*.rb`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Each metric is computed in exactly one place
- [ ] `probability_ranges` removed or spec-covered
- [ ] Existing eval specs and CI summary spec pass unchanged
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
- EvaluationAnalysis#metrics is the single definition of totals, rates and per-rule counts; the runner stores it. probability_ranges and the duplicated ratio removed. EvaluationSummary keeps only its CI-contract validation.
