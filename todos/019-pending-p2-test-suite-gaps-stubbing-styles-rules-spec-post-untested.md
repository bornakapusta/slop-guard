---
status: pending
priority: p2
issue_id: "019"
tags: [code-review, test-coverage, quality]
dependencies: []
---

# Test-suite gaps: no Rules spec, JevClient#post untested, three stubbing styles, multi-behaviour examples

## Problem Statement

The suite is behaviour-named, never hits the provider, and git_source_spec proves no execution and no working-tree mutation. But several important behaviours have no spec, the client is stubbed three different ways (so verify_partial_doubles does not protect the `ask` signature), and several examples bundle four behaviours so a failure does not say what broke. Line coverage is 78.8% with bin/* at 0% (subprocess-only) and jev_client.rb at 75%.

## Findings

- No `spec/slop_guard/rules_spec.rb`: `validate_questions!`, `low >= high`, unknown candidate reference, `any_positive` optional, `repository: true` swapping only G3, and custom directory are exercised only via a subprocess in `git_source_spec.rb:184-197`.
- `JevClient#post` (`jev_client.rb:69-94`): 128 KiB cap, timeout clamping, mid-stream deadline check untested; specs stub the private `post` and poke `@read`.
- Stubbing: `Object.new` + `define_singleton_method` (evaluator_spec, design_rules_spec, cli_spec, runner_spec), `instance_double(JevClient)` (git_source_spec), `double('client')` (evaluator_spec). `Dataset.new(File.join(ROOT, 'eval'))` repeated nine times.
- Multi-behaviour examples: `cli_spec.rb:21-42`, `git_source_spec.rb:115-127`, `budget_spec.rb:14-23`.
- Untested Evaluator branches: `evaluator.rb:72-76` (no scenarios), `94-96` (unclear applicability), `155-159` (nil anchor), G2 failures path, `any_positive` at 133-138, `124-127` (no changed candidate).
- Untested Snapshot behaviours: `anchor` fallback rewritten on this branch (`snapshot.rb:71-73`), `changed_candidates`, "More than 50 changed files", `before_changed` selection.
- GitSource: submodule gap, explicit `--head`, 100755 blob, output `limit:`/timeout, 1 MiB bundle, `GIT_DIR` scrubbing, non-repository path, criss-cross merge base untested.
- Expectations (>12 scenarios, digest ids, unrelated heading ends section) and Candidates (`require_relative` missing target, uninspected `require`) untested. Budget `record_usage` and exact `reserved + RESERVATION == review_limit` boundary untested.

## Proposed Solutions

### Option 1: Shared stub helper plus targeted specs

**Approach:** Add `spec/support/stub_client.rb` returning an `instance_double(SlopGuard::JevClient)` driven by a block, and a `fixture_dataset` helper. Add `rules_spec.rb`. Inject an `http:` factory into JevClient and test `post` through it. Split multi-behaviour examples. Add the listed Evaluator, Snapshot, GitSource, Expectations and Candidates cases. Consider rubocop-rspec for MultipleExpectations/EmptyLineBetweenExamples.

**Pros:**
- Signature-verified stubs
- Failures localise
- Covers the branch-new anchor logic

**Cons:**
- A day of test writing

**Effort:** Large (1 day)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `spec/spec_helper.rb`
- `spec/slop_guard/*.rb`
- `spec/eval/*.rb`
- `lib/slop_guard/jev_client.rb:69-94`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] One client stubbing helper used everywhere
- [ ] `rules_spec.rb` exists and covers threshold/reference validation
- [ ] JevClient#post covered without stubbing private methods
- [ ] Each listed untested branch has at least one example
- [ ] No example asserts more than one behaviour
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



### 2026-09-20 - 019a done

**By:** Claude Code (Phase 1, branch `fix/review-phase-1`)

**Actions:**
- `spec/support/stub_client.rb`: `stub_client { |state, questions| }` returns an `instance_double(SlopGuard::JevClient)`; `fixture_dataset` helper. All `Object.new`/`define_singleton_method`/`double('client')` stubs and nine `Dataset.new(ROOT/eval)` sites migrated.
- `spec/slop_guard/rules_spec.rb` added: default load and revision, repository-mode G3 substitution, custom directory, inverted/equal/out-of-range thresholds, unknown candidate refs, empty lists, optional `any_positive`, blank text, missing key/file, malformed YAML.
- Remaining: 019b GitSource specs (Phase 2); 019c (Phase 5).

