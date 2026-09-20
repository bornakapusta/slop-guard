---
status: complete
priority: p3
issue_id: "022"
tags: [code-review, architecture]
dependencies: [010]
---

# LimitExceeded conflates "input too large" with budget/deadline failures

## Problem Statement

GitSource raises LimitExceeded for oversized files, too many files and an oversized bundle. Evaluator treats LimitExceeded as an operational failure and marks the report `failed`. Callers cannot tell "retry later" from "this PR is too big", which a bot needs for retry logic and user messaging.

## Findings

- `git_source.rb:72,76,83` raise LimitExceeded for size bounds.
- `evaluator.rb:29-32` rescues LimitExceeded as failure.
- `budget.rb:28-37` and `jev_client.rb:27,32,58` use LimitExceeded for budget/deadline.

## Proposed Solutions

### Option 1: InputTooLarge < InvalidInput

**Approach:** Add `InputTooLarge < InvalidInput` for size bounds; keep LimitExceeded for budget/deadline. Map to a distinct exit code in todo 010.

**Pros:**
- Clear retry semantics

**Cons:**


**Effort:** Small (1 hour)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard.rb:14-17`
- `lib/slop_guard/git_source.rb:72-83`
- `lib/slop_guard/evaluator.rb:29-32`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Oversized input raises an InvalidInput subclass
- [ ] Budget exhaustion still raises LimitExceeded
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
- `InputTooLarge < InvalidInput` for size bounds in GitSource, GitHubSource and the CLI input document; budget and deadline keep LimitExceeded. Oversized files are skipped with a gap in both adapters.
