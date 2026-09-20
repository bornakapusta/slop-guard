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


