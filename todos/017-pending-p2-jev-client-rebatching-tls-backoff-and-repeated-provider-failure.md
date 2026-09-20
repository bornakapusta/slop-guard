---
status: pending
priority: p2
issue_id: "017"
tags: [code-review, performance, reliability, budget]
dependencies: []
---

# JevClient: O(Q²) re-serialisation, new TLS connection per request, fixed retry delay, and provider failure repeated per rule

## Problem Statement

The batcher re-encodes model, state and all accumulated questions for every question added (about 10 MiB of JSON per scenario at 100 test candidates). Each request opens a fresh Net::HTTP, paying DNS plus TLS handshake (100-300 ms) for 10-20 requests per review. Retry delay is a fixed 1 s with no jitter, so concurrent bot clients would retry in lockstep. Evaluator catches ProviderError per rule and continues, so a revoked key produces four identical failures and burns four reservations per review. `Timeout.timeout` wraps Net::HTTP even though per-operation timeouts are already set.

## Findings

- `lib/slop_guard/jev_client.rb:30-31` re-encodes per question.
- `lib/slop_guard/jev_client.rb:73-79` new Net::HTTP per post; `jev_client.rb:81` Timeout wrapper.
- `lib/slop_guard/jev_client.rb:126-134` fixed 1.0 default delay.
- `lib/slop_guard/evaluator.rb:27-32` per-rule rescue continues after non-retryable ProviderError.
- `JevClient#post` is untested: specs stub the private method (`jev_client_spec.rb:23,106`).

## Proposed Solutions

### Option 1: Encode once, reuse connection, abort after fatal provider error

**Approach:** Encode state once and keep a running byte count of encoded questions. Hold one started Net::HTTP per client and reopen on EOFError/IOError. Exponential backoff with jitter capped at `budget.remaining`. Drop the outer Timeout in favour of the native timeouts already clamped to the deadline. In Evaluator, after a non-retryable ProviderError (401/403/4xx) mark remaining rules failed without new requests. Inject an `http:` factory so `post` becomes testable.

**Pros:**
- Removes wasted reservations and latency
- Makes the 128 KiB cap and deadline checks testable

**Cons:**
- Connection reuse needs care on errors

**Effort:** Medium (3-4 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/jev_client.rb`
- `lib/slop_guard/evaluator.rb:27-32`
- `spec/slop_guard/jev_client_spec.rb`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] State encoded once per `ask`
- [ ] A 401 stops further requests in the same review
- [ ] JevClient#post covered without stubbing private methods
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


