---
status: pending
priority: p3
issue_id: "024"
tags: [code-review, agent-native]
dependencies: [004]
---

# CLI conveniences for agents: expectations from stdin, arbitrary --input FILE, --show-rules

## Problem Statement

Expectations must be a file, so a bot holding the PR body as a string must write a temp file. Case mode only accepts the built-in eval dataset; there is no way to feed an arbitrary before/files/pr_body hash even though Snapshot accepts exactly that. `--inspect` prints only `rules_revision`, so learning thresholds or question text requires reading YAML and knowing about the G3 substitution.

## Findings

- `bin/review:23,35` file-only expectations.
- `bin/review:45-46` dataset-only case input.
- `bin/review:53` only `rules_revision`; `rules.rb:10-14` substitution invisible to callers.

## Proposed Solutions

### Option 1: Three small flags

**Approach:** `--expectations -` reads stdin; `--input FILE` feeds Snapshot directly; `--show-rules` prints `Rules#definitions`, revision and which files were used; include resolved profile in `--inspect`.

**Pros:**
- Bot can drive the CLI without the library if needed

**Cons:**
- More surface to document

**Effort:** Small-Medium (2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `bin/review`
- `docs/local-repository-review.md`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Each flag documented in --help and README
- [ ] cli_spec covers each
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


