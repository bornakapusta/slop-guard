---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, quality, reliability]
dependencies: []
---

# Corrupt request ledger line escapes as raw JSON::ParserError

## Problem Statement

Budget#reserve! parses every ledger line with JSON.parse and nothing rescues JSON::ParserError. A truncated `requests.jsonl` (kill mid-write, disk full) crashes with a backtrace instead of a project error. bin/review rescues only SlopGuard::Error, OptionParser::ParseError, SystemCallError and Psych::Exception. Reproduced: writing `garbage\n` to a ledger and calling `reserve!` raises JSON::ParserError.

## Findings

- `lib/slop_guard/budget.rb:36` `file.each_line.sum { |line| JSON.parse(line).fetch('reserved_usd', 0) }` has no rescue.
- `bin/review:70-75` does not rescue JSON::ParserError; `bin/evaluate:69` does, so the two CLIs behave differently.
- The eval runner shares one ledger across all cases in a run (`eval_runner.rb:84`), so one bad line poisons the whole session.

## Proposed Solutions

### Option 1: Rescue in reserve! and fail closed

**Approach:** Rescue JSON::ParserError (and KeyError/TypeError for shape) inside `reserve!` and raise `InvalidInput, "Request ledger is corrupt: #{path}"`. Add a spec with a garbage line.

**Pros:**
- Fails closed: no request is made against an unknown total
- Consistent error taxonomy

**Cons:**
- Operator must delete or repair the ledger manually

**Effort:** Small (30 min)

**Risk:** Low

---

### Option 2: Skip unparsable trailing line only

**Approach:** Treat a final partial line as a torn write and ignore it, but fail on any other bad line.

**Pros:**
- Recovers from the common kill-mid-write case

**Cons:**
- Slightly more logic; a torn line still counted a reservation that was not persisted

**Effort:** Small (1 hour)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/budget.rb:34-43`
- `spec/slop_guard/budget_spec.rb`
- `bin/review:70-75`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] A ledger containing an invalid line makes `reserve!` raise SlopGuard::InvalidInput
- [ ] No request is sent when the ledger is unreadable
- [ ] Spec covers the corrupt-ledger case
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



### 2026-09-20 - Fixed

**By:** Claude Code (Phase 1, branch `fix/review-phase-1`)

**Actions:**
- `Budget#ledger_total` parses each line, requires an object with a numeric `reserved_usd`, and maps `JSON::ParserError`/`TypeError` to `InvalidInput "Request ledger is corrupt: <path>"` inside the flock, so no reservation is written.
- `spec/slop_guard/budget_spec.rb` covers a garbage line, a non-object line and a non-numeric amount, and asserts `JevClient#post` is never called and `attempts` stays 0.

