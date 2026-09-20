---
status: pending
priority: p3
issue_id: "023"
tags: [code-review, quality]
dependencies: [009]
---

# Split the largest methods flagged by RuboCop Metrics outside the eval pipeline

## Problem Statement

RuboCop Metrics (informational in CI) flags Snapshot#initialize (ABC 81, CC 21), Evaluator#evaluate_design (CC 28), Evaluator#evaluate_tests (CC 19, 45 lines), Dataset#validate! (CC 22) and Candidates#check_call (CC 22). The eval-pipeline offenders are covered by todo 013.

## Findings

- `snapshot.rb:10-46` mixes validation, profile filtering, diffing and candidate extraction.
- `evaluator.rb:65-153` two long decision procedures.
- `dataset.rb:72-114` one long validator.
- `candidates.rb:63-92` three checks in one method.

## Proposed Solutions

### Option 1: Extract by responsibility

**Approach:** `Snapshot`: `validate_tree!`, `apply_profile`. `Evaluator`: `scenario_questions`, `classify_coverage`, `classify_design`. `Dataset#validate!`: `validate_manifest!`, `validate_labels!`. `Candidates#check_call`: `check_unsupported`, `check_fixture`, `check_require`.

**Pros:**
- Each piece unit-testable
- Metrics report shrinks

**Cons:**
- Mechanical

**Effort:** Medium (2-3 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/snapshot.rb:10-46`
- `lib/slop_guard/evaluator.rb:65-153`
- `lib/slop_guard/dataset.rb:72-114`
- `lib/slop_guard/candidates.rb:63-92`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No method over 30 lines in the listed files
- [ ] Behaviour unchanged; specs pass
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



### 2026-09-20 - Mostly done

**By:** Claude Code (Phases 2-5, branch `refactor/review-phases-2-6`)

**Actions:**
- Snapshot#initialize (validate_trees!, apply_profile), Evaluator (RuleRun with scenario_questions/classify_scenario/classify_candidate/classify_design), Dataset#validate! (validate_manifest!/validate_labels!/validate_anchor!) and Candidates#check_call split. EvalRunner#run split into prepare/review_case/finalize. EvaluationAnalysis#validate! still long.

**Metrics count:** RuboCop Metrics offenses rose from 199 (main) to 243 on this branch despite the splits above, because the new CLI, GitSource, Profile and Evaluator methods exceed MethodLength 10 and AbcSize 17. Informational in CI; consider raising Metrics thresholds to realistic values in .rubocop.yml or continuing extraction.
