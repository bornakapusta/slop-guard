---
status: pending
priority: p3
issue_id: "021"
tags: [code-review, quality, ruby]
dependencies: []
---

# Ruby clarity cleanups: hidden U+200C, nested ternary, compressed booleans, unfrozen URI, ternary assignment

## Problem Statement

Several small readability issues that RuboCop does not catch but a reader will trip over.

## Findings

- `lib/slop_guard/report.rb:34` contains an invisible U+200C (zero-width non-joiner) after `@` inside a quoted string (confirmed by hexdump, bytes e2 80 8c). Write it as `"@\u200C"` with a comment explaining it defangs @-mentions.
- `lib/slop_guard/evaluator.rb:36-40` nested ternary inside if/else; expand to if/elsif/else.
- `lib/slop_guard/evaluator.rb:132-149` five booleans (`yes`, `no`, `exempt`, `absent`, `alternatives`) drive a four-way branch; rename to `positives_high`, `negatives_low`, `any_negative_high`, `any_positive_low`. Note `any_positive` has exactly one consumer (`config/rules/g3.yml:14`) and must stay for benchmark preservation; say so in a comment.
- `lib/slop_guard/jev_client.rb:9` `ENDPOINT = URI(...)` is mutable; `.freeze`.
- `lib/slop_guard/dataset.rb:54` `cond ? after.delete(path) : after[path] = value` relies on ternary/assignment precedence; use if/else.
- `lib/slop_guard/candidates.rb:65-66,69-70` symbol arrays wrapped mid-expression; hoist to `DYNAMIC_EXAMPLE_ITERATORS` and `FILE_READS` constants. `path.start_with?('spec/')` appears five times and `node.arguments&.arguments&.first` three times; add `spec?(path)` and `first_argument(node)` and split `check_call`.
- `lib/slop_guard/snapshot.rb:22-23` autocorrected array wrap `['', '..',\n '.']`; `snapshot.rb:66-75` anchor predicate should be named `production_ruby_path?` and reused at line 50.
- `lib/slop_guard/report.rb:9-21` `shared_test_concerns` dedupe fires only when two explicit IDs share identical text in both sections; near-dead, revisit with todo 011.
- `bin/review:59` repeats the API-key check JevClient#initialize performs, after already creating the tmp directory; remove or move ahead of Budget.
- Naming: `EvalRunner` vs `EvaluationAnalysis`/`EvaluationSummary`; `--repeats` vs `repetitions:`; `Candidates#items`.

## Proposed Solutions

### Option 1: Sweep in one PR

**Approach:** Apply each item; none changes behaviour except making the U+200C visible.

**Pros:**
- Cheap
- Improves review of later refactors

**Cons:**


**Effort:** Small (1-2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/report.rb:34`
- `lib/slop_guard/evaluator.rb:36-40,132-149`
- `lib/slop_guard/jev_client.rb:9`
- `lib/slop_guard/dataset.rb:54`
- `lib/slop_guard/candidates.rb:38-92`
- `lib/slop_guard/snapshot.rb:22,50,66-75`
- `bin/review:59`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No invisible characters in source (`grep -P "[\x{200B}-\x{200D}]"` finds none)
- [ ] RuboCop still clean
- [ ] Specs pass unchanged
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



### 2026-09-20 - Partially done

**By:** Claude Code (Phase 1, branch `fix/review-phase-1`)

**Actions:**
- Done: U+200C moved to `Report::MENTION_BREAK` with a comment; evaluator status if/elsif; design booleans renamed (`positives_high`, `negatives_low`, `any_negative_high`, `any_positive_low`, `ruled_out`) with a comment on `any_positive`; `ENDPOINT.freeze`; `dataset.rb` ternary assignment to if/else; `bin/review` single key check via an `api_key` local.
- Remaining (Phase 5 with 023): `candidates.rb` constants and helpers; `snapshot.rb` `production_ruby_path?`; naming items.


### 2026-09-20 - Mostly done

**By:** Claude Code (Phases 2-5, branch `refactor/review-phases-2-6`)

**Actions:**
- Candidates helpers and constants, snapshot anchorable? predicate landed with Phases 3-5. Naming items (EvalRunner vs EvaluationAnalysis, --repeats vs repetitions:) left as is.
