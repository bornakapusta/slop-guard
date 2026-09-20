---
status: pending
priority: p2
issue_id: "014"
tags: [code-review, quality, budget]
dependencies: []
---

# Byte/file limits and per-token price are duplicated as magic numbers

## Problem Statement

16 KiB appears in snapshot, git_source (four times), and bin/review (as 16_385); 1 MiB in dataset and git_source; 100 files in snapshot and git_source; the per-token price `0.042 / 1_000_000` in budget and eval_runner; request limits 28 KiB, 56 KiB and 128 KiB inline in jev_client. A price or limit change is a multi-file edit with no single source of truth, and the evidence-selection work (todo 001) needs one shared byte budget.

## Findings

- 16 KiB: `snapshot.rb:16,29`, `git_source.rb:22,72,79,102`, `bin/review:35`.
- 1 MiB: `dataset.rb:19`, `git_source.rb:83`. 100 files: `snapshot.rb:32`, `git_source.rb:76`.
- Price: `budget.rb:6`, `eval_runner.rb:92`. Request caps: `jev_client.rb:26,31,87`.

## Proposed Solutions

### Option 1: Named constants on the owning class

**Approach:** Add `JevClient::USD_PER_INPUT_TOKEN`, `JevClient::MAX_STATE_BYTES`, `MAX_REQUEST_BYTES`, `MAX_RESPONSE_BYTES`, and a `SlopGuard::Limits` module (or Profile fields) for FILE_BYTES, FILE_COUNT, BUNDLE_BYTES, BODY_BYTES; reference them from bin/review.

**Pros:**
- One edit per change
- Names document intent

**Cons:**


**Effort:** Small (1 hour)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/budget.rb:6`
- `lib/slop_guard/eval_runner.rb:92`
- `lib/slop_guard/jev_client.rb:26,31,87`
- `lib/slop_guard/git_source.rb`
- `lib/slop_guard/snapshot.rb`
- `bin/review:35`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No numeric limit literal appears in more than one file
- [ ] Price constant referenced from both Budget and EvalRunner
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


