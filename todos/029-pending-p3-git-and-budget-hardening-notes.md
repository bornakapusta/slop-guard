---
status: pending
priority: p3
issue_id: "029"
tags: [code-review, security, budget]
dependencies: []
---

# Hardening: per-run session ledger, repo-local Git config trust, upward repo discovery, negative timeout race

## Problem Statement

Four hardening items that are not exploitable as shipped but narrow guarantees the docs imply.

## Findings

- Session ledger: `bin/review:58-61` creates a fresh `tmp/reviews/<ts>-<pid>/requests.jsonl` per invocation, so the $2 `session_limit` only ever sees one run; per-review caps (20 attempts, $0.10, 120 s) still hold. Only bin/evaluate shares a ledger (`eval_runner.rb:84`).
- Repo-local `.git/config` is trusted (global/system disabled at `git_source.rb:91-94`). `core.fsmonitor`/`core.pager` confirmed not executed by the four plumbing commands. On Git < 2.46 `GIT_NO_LAZY_FETCH` is ignored, so a partial clone with an `ext::` promisor URL plus `protocol.allow=always` could execute on lazy fetch.
- Repository discovery walks upward: `--repo /repo/sub` silently reviews the enclosing repo (confirmed).
- `jev_client.rb:76-82` `[5, budget.remaining].min` can go negative if the deadline passes between `reserve!` and `post`, raising ArgumentError that bin/review does not rescue.
- `.env` is mode 644 on this machine.

## Proposed Solutions

### Option 1: Four small changes

**Approach:** Point bin/review at a shared dated ledger or document that session_limit applies to evaluation runs only. Pass `-c protocol.allow=never -c core.fsmonitor=false` on every Git call and refuse Git < 2.46. Compare `git rev-parse --show-toplevel` with the realpath (or set GIT_CEILING_DIRECTORIES). Clamp timeouts with `.clamp(0.001, ...)`. Recommend `chmod 600 .env` in README.

**Pros:**
- Closes documented gaps cheaply

**Cons:**


**Effort:** Small (1-2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `bin/review:58-61`
- `lib/slop_guard/git_source.rb:89-97`
- `lib/slop_guard/jev_client.rb:76-82`
- `README.md`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Session-limit semantics documented or enforced across reviews
- [ ] Git invoked with protocol.allow=never
- [ ] Subdirectory --repo is rejected or normalised explicitly
- [ ] Timeouts never negative
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
- protocol.allow=never and core.fsmonitor=false on every Git call; --repo must be the repository root; timeouts clamped; session-ledger semantics and chmod 600 documented. Git < 2.46 is documented, not refused (ubuntu-24.04 CI ships 2.43).
