---
status: complete
priority: p2
issue_id: "009"
tags: [code-review, quality, architecture]
dependencies: []
---

# Evaluator and GitSource carry per-call state in instance variables; not reentrant

## Problem Statement

Evaluator#call sets @snapshot, @id, @rule and @result inside the rules loop and every private method reads them implicitly. `call` is not reentrant, private methods cannot be reasoned about in isolation, and a webhook worker sharing an Evaluator would corrupt results. GitSource#input similarly resets @gaps, @skipped and @bytes as scratch space that `tree` mutates. Evaluator also reads JevClient::MODEL from the concrete class, so stub clients and future providers report the wrong model.

## Findings

- `lib/slop_guard/evaluator.rb:13-20` ivar assignment per iteration; `evaluator.rb:57-63,155-173` read hidden state.
- `lib/slop_guard/evaluator.rb:53` `(@result['question_fingerprints'] ||= [])` makes report shape vary; `evaluation_analysis.rb:116-120` has a legacy branch because of it.
- `lib/slop_guard/git_source.rb:31-33,60-83` scratch ivars.
- `lib/slop_guard/evaluator.rb:41` and `eval_runner.rb:19` read `JevClient::MODEL`.

## Proposed Solutions

### Option 1: Per-rule run object

**Approach:** Extract `RuleRun` (id, rule, snapshot, result) or `evaluate_rule(id, rule, snapshot)` returning the result hash; make `high?`/`low?` take the rule. Initialise `question_fingerprints: []` eagerly. Have `tree` return a Data.define(:files, :gaps, :skipped). Add `client.model` to the client interface.

**Pros:**
- Reentrant, testable in isolation
- Stable report shape

**Cons:**
- Mechanical refactor of ~150 lines

**Effort:** Medium (2-4 hours)

**Risk:** Low

---

### Option 2: Document non-reusability

**Approach:** Add a class comment "one instance per review" and leave the code.

**Pros:**
- Zero risk

**Cons:**
- Debt remains for the bot worker

**Effort:** Small

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/evaluator.rb`
- `lib/slop_guard/git_source.rb:21-87`
- `lib/slop_guard/eval_runner.rb:19`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Two concurrent `call`s on one Evaluator produce independent reports
- [ ] `question_fingerprints` always present in results
- [ ] Stub clients report their own model string
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



### 2026-09-20 - Fixed

**By:** Claude Code (Phases 2-5, branch `refactor/review-phases-2-6`)

**Actions:**
- `Evaluator::RuleRun` holds per-rule state; `Evaluator#call` is reentrant. `GitSource::Tree` replaces scratch ivars. Fingerprints eager. `client.model` on the client interface.
