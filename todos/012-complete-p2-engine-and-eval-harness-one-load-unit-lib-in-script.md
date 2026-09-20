---
status: complete
priority: p2
issue_id: "012"
tags: [code-review, architecture]
dependencies: []
---

# Engine and evaluation harness load as one unit; library classes live in script/

## Problem Statement

lib/slop_guard.rb requires dataset, eval_runner and evaluation_analysis alongside the engine, so a bot process loads the harness and bin/review's demo path depends on Dataset. Meanwhile SlopGuard::EvaluationSummary and SlopGuard::ThresholdCalibration are defined in script/*.rb, required by specs via relative paths, and not mentioned in AGENTS.md. AGENTS.md asks to keep product scope separate from the eval fixture.

## Findings

- `lib/slop_guard.rb:24-27` require list mixes engine and harness.
- `script/evaluation_summary.rb:8` and `script/calibrate_thresholds.rb:12-18` define library classes; `SingleRule < Rules` calls `super()` to load four YAML files then discards them.
- Dataset#validate! hard-codes 16/8 case counts and rule IDs (`dataset.rb:73,91`), which is a fixture contract, not engine logic.

## Proposed Solutions

### Option 1: lib/slop_guard/eval/ namespace

**Approach:** Move Dataset, EvalRunner, EvaluationAnalysis, EvaluationSummary and ThresholdCalibration under lib/slop_guard/eval/ with `require 'slop_guard/eval'`; keep lib/slop_guard.rb engine-only; make script/ and bin/evaluate thin entry points. Give Rules a `from_definitions` constructor so calibration does not subclass with `super()`.

**Pros:**
- Clear product/harness boundary per AGENTS.md
- Specs require normal lib paths

**Cons:**
- File moves touch many requires and docs

**Effort:** Medium (2-3 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard.rb:24-27`
- `script/evaluation_summary.rb`
- `script/calibrate_thresholds.rb`
- `bin/evaluate`
- `spec/ci/evaluation_summary_spec.rb`
- `spec/eval/threshold_calibration_spec.rb`
- `AGENTS.md`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] `require 'slop_guard'` loads no eval harness classes
- [ ] No class definitions remain in script/
- [ ] AGENTS.md structure section updated
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
- Dataset, EvalRunner, EvaluationAnalysis, EvaluationSummary and ThresholdCalibration live under lib/slop_guard/eval/ behind `require "slop_guard/eval"`; script/ holds thin entry points; `Rules.from_definitions` replaces the SingleRule subclass.
