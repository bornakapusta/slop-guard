---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, security, budget, agent-native]
dependencies: []
---

# Live mode loads .env unconditionally; unset env var silently falls back to a stored key

## Problem Statement

bin/review and bin/evaluate call Dotenv.load in live mode whenever TYPESAFE_API_KEY is not already set. A CI job or agent that unsets the variable to run a "no credentials" probe still gets whatever the ignored .env holds. During this review an agent ran `env -u TYPESAFE_API_KEY bin/review g1-violation --live` expecting the configured error and instead made 7 real reserved requests (under $0.02, report in tmp/reviews/20260920T083648-77317). Only an empty-string variable blocks the fallback.

## Findings

- `bin/review:57` and `bin/evaluate:57` `Dotenv.load(File.join(SlopGuard::ROOT, '.env'))` with no opt-out.
- Dotenv.load does not override an already-set variable, so CI secrets win when set; the problem is the unset case.
- README documents .env but not precedence or how to disable it.
- The budget guards worked as intended: the run was capped at 7 reservations.

## Proposed Solutions

### Option 1: Explicit opt-in for .env

**Approach:** Only load .env when `--env-file PATH` is passed or `SLOP_GUARD_ENV_FILE` is set; otherwise require the variable in the environment. Document precedence.

**Pros:**
- No hidden credential source
- Predictable for agents and CI

**Cons:**
- Local users add one flag or an export

**Effort:** Small (1 hour)

**Risk:** Low

---

### Option 2: Skip .env when CI or SLOP_GUARD_NO_DOTENV is set

**Approach:** Keep default local convenience but disable under `CI=true` or an explicit env var.

**Pros:**
- Zero change for local workflow

**Cons:**
- Still a hidden source locally; the incident above happened locally

**Effort:** Small (30 min)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `bin/review:57`
- `bin/evaluate:57`
- `README.md`
- `.env.example`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Running `--live` with TYPESAFE_API_KEY unset and no explicit env-file flag exits 2 with "not configured"
- [ ] README documents credential precedence
- [ ] cli_spec covers the unset-variable case
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


