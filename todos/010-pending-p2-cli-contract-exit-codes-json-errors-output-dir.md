---
status: pending
priority: p2
issue_id: "010"
tags: [code-review, agent-native, quality]
dependencies: [004]
---

# CLI contract: coarse exit codes, prose-only errors, hard-coded output directory

## Problem Statement

bin/review exits 2 for invalid input, incomplete evidence, provider failure and unreadable config alike; bin/evaluate uses 1 for eval failure. A bot cannot distinguish "bad input" from "provider down, retry" from "review ran with gaps, post partial results" without parsing prose stderr. `--json` applies only to successful `--live`; errors are never JSON and `Cannot read repository input or trusted configuration: Errno::ENOENT` discards the path. Reports and ledgers are written under the Slop Guard checkout at ROOT/tmp with the path announced only in a stderr sentence.

## Findings

- `bin/review:68,72,75` all exit 2; `bin/evaluate:65,71` exit 1 and 2.
- `bin/review:73-74` rescues SystemCallError broadly, so an EACCES writing tmp/reviews is reported as a read failure.
- `bin/review:58,61,66` hard-code ROOT/tmp/reviews and announce via prose.
- `--json` is silently ignored under `--inspect` (`bin/review:14,67`).

## Proposed Solutions

### Option 1: Documented exit-code table and JSON error envelope

**Approach:** Define 0 complete, 1 incomplete (report still valid), 2 usage/invalid input, 3 provider/budget/operational failure. Under `--json`, emit `{"error": {"class":..., "message":..., "path":...}}`. Add `--output DIR` (or `SLOP_GUARD_OUTPUT_DIR`) and include `report_path`/`ledger_path` in JSON output. Narrow rescues to read paths. Document in --help and README.

**Pros:**
- Bots and CI can branch without parsing prose
- Consistent across the three bins

**Cons:**
- Exit-code change is a documented behaviour change

**Effort:** Medium (2-3 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `bin/review:56-76`
- `bin/evaluate:57-72`
- `bin/analyze-evaluation`
- `README.md`
- `docs/local-repository-review.md`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Exit codes distinguish complete / incomplete / invalid input / operational failure
- [ ] Errors under --json are machine-readable
- [ ] Output directory is configurable and reported in JSON
- [ ] cli_spec asserts each exit code
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


