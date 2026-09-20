---
status: pending
priority: p2
issue_id: "006"
tags: [code-review, quality]
dependencies: []
---

# Dataset#labels raises NoMethodError for an unknown case id

## Problem Statement

Dataset#labels calls `entry.fetch('labels')` on nil when the id is unknown, raising NoMethodError, while Dataset#input raises InvalidInput "Unknown case ID" for the same condition. Reproduced.

## Findings

- `lib/slop_guard/dataset.rb:67-70` has no nil guard.
- `lib/slop_guard/dataset.rb:41-42` handles the same case correctly.

## Proposed Solutions

### Option 1: Shared entry lookup

**Approach:** Extract `entry_for(id)` raising InvalidInput and use it from `input` and `labels`. Add a spec.

**Pros:**
- One code path
- Consistent error class

**Cons:**


**Effort:** Small (15 min)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/dataset.rb:40-70`
- `spec/eval/runner_spec.rb`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] `labels('unknown')` raises SlopGuard::InvalidInput
- [ ] Spec added
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


