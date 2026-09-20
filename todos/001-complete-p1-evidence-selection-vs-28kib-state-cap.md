---
status: complete
priority: p1
issue_id: "001"
tags: [code-review, architecture, performance, blocker]
dependencies: []
---

# Add an evidence-selection layer: whole-tree state exceeds the 28 KiB provider cap

## Problem Statement

Snapshot#state sends every permitted head file, numbered, plus changed before-files. JevClient refuses any request whose state exceeds 28 KiB without truncation. GitSource admits up to 100 files / 1 MiB. So repository mode accepts inputs that live review can never send. Measured on this repository: `bin/review --repo . --base main --inspect` yields 122,213 state bytes for 31 files, four times the cap. As a GitHub PR bot this fails on nearly every real repository, after all Git reads have been done.

## Findings

- `lib/slop_guard/snapshot.rb:55-64` builds `head` from all permitted files and `before_changed` from changed files.
- `lib/slop_guard/jev_client.rb:26` raises LimitExceeded when `state_bytes + question > 28 * 1024`.
- `lib/slop_guard/git_source.rb:72-83` bounds are 16 KiB/file, 100 files, 1 MiB total, roughly 40x looser than the client can consume.
- docs/local-repository-review.md already admits "a large inspected bundle can therefore be refused by live review without truncating evidence"; the limit is documented but makes the product goal unreachable.
- Evaluator treats the resulting LimitExceeded as an operational failure (`evaluator.rb:29-32`), so the report says `failed` rather than "input too large".

## Proposed Solutions

### Option 1: Diff-scoped context selection

**Approach:** Insert a selection step between Snapshot and `state`: include changed files, spec files whose candidates reference changed methods/classes, and the `require_relative` closure Candidates already computes. Send unchanged files only as a path list. Record excluded files as gaps. Make the byte budget a constructor parameter shared by selector and client.

**Pros:**
- Honest: evidence is selected, never truncated
- Makes real repositories reviewable
- Reuses Candidates data already computed

**Cons:**
- Changes `state` shape, so rules revision/benchmark evidence must be re-established per docs/evaluation.md
- Selection heuristics need their own specs

**Effort:** Large (1-2 days)

**Risk:** Medium

---

### Option 2: Align bounds only

**Approach:** Lower GitSource limits so the tree cannot exceed what the client accepts, and fail fast in `--inspect` with a clear "too large for live review" message.

**Pros:**
- Small change
- Fails before Git reads complete

**Cons:**
- Does not make the tool useful on real repositories
- Only makes the ceiling visible

**Effort:** Small (1-2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/snapshot.rb:55-64`
- `lib/slop_guard/jev_client.rb:26-31`
- `lib/slop_guard/git_source.rb:72-83`
- `lib/slop_guard/candidates.rb`
- `docs/local-repository-review.md`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] A repository with >28 KiB of permitted source but a small diff produces a live-reviewable state
- [ ] Excluded files appear as explicit gaps in the report
- [ ] `--inspect` reports whether the state fits the live limit
- [ ] Benchmark evidence is re-frozen per docs/evaluation.md if `state` shape changes
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options

## Notes

Option 2 is a stopgap that can ship first. Option 1 is the real fix and is the top blocker for GitHub bot use.


### 2026-09-20 - Fixed

**By:** Claude Code (Phases 2-5, branch `refactor/review-phases-2-6`)

**Actions:**
- Snapshot#selected_paths sends changed files, test files, required files and their require_relative closure; other permitted files are listed by path. `--inspect` reports state_bytes, live_limit_bytes and fits_live_limit.
