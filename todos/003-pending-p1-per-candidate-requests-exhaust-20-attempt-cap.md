---
status: pending
priority: p1
issue_id: "003"
tags: [code-review, performance, architecture, budget]
dependencies: []
---

# Per-scenario and per-candidate requests exhaust the 20-attempt review budget on ordinary PRs

## Problem Statement

Budget caps a review at 20 attempts and $0.10. Evaluator issues one request per G1 scenario, one per G2 scenario, one global plus one per changed method for G3, and one global plus one per changed class for G4. With 12 scenarios (the maximum before a gap) six attempts remain for every changed method and class. A PR touching seven methods raises LimitExceeded inside G3, the report becomes `failed`, and the CLI exits 2. Retries on 429 also consume attempts, so a rate-limited provider shrinks this further. Reviews fail on ordinary PRs, not just large ones.

## Findings

- `lib/slop_guard/budget.rb:9,29` `max_attempts: 20`, `review_limit: 0.10` (37 reservations).
- `lib/slop_guard/evaluator.rb:77-91` one `ask` per scenario; `evaluator.rb:128-131` one `ask` per design candidate.
- `lib/slop_guard/jev_client.rb:48-61` calls `budget.reserve!` on every retry loop iteration.
- JevClient#ask already splits a question hash into 56 KiB batches (`jev_client.rb:21-42`), so batching more questions per `ask` is supported.

## Proposed Solutions

### Option 1: Batch all candidate questions per rule

**Approach:** Build one questions hash for all candidates (or all scenarios) and call `ask` once per rule; the client splits it into request-sized batches. Keep the sequential `applicable`/`global` gate as a separate first call.

**Pros:**
- G3/G4 become 1-2 requests regardless of candidate count
- No budget constant changes

**Cons:**
- Question IDs must be namespaced per candidate (already done for tests via `exercise_<id>`)
- Changes question fingerprints; benchmark evidence must be re-established

**Effort:** Medium (half a day)

**Risk:** Medium

---

### Option 2: Count requests, not retries, and align max_attempts with review_limit

**Approach:** Only increment `attempts` on a non-retryable response and set `max_attempts` to `review_limit / RESERVATION`.

**Pros:**
- Small change

**Cons:**
- Still one request per candidate; latency stays linear in PR size

**Effort:** Small (1 hour)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/evaluator.rb:65-153`
- `lib/slop_guard/budget.rb:9-46`
- `lib/slop_guard/jev_client.rb:21-67`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] A snapshot with 12 scenarios and 10 changed methods completes without LimitExceeded under default budget
- [ ] Spec asserts request count for a multi-candidate design rule
- [ ] Latency per review is documented as O(rules) not O(candidates)
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


