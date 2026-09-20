---
status: complete
priority: p2
issue_id: "007"
tags: [code-review, architecture, quality]
dependencies: []
---

# Rule IDs and rule kinds are hard-coded in about nine places

## Problem Statement

The set `%w[G1 G2 G3 G4]` and the kind test `%w[G1 G2].include?(id)` are repeated across the evaluator, rules loader, report renderer, dataset validator, eval runner, analysis and the summary script. Adding a rule or a project-specific rule touches roughly nine sites, and the YAML files carry no `kind` field even though the evaluator dispatches tests vs design on it.

## Findings

- Kind test: `evaluator.rb:28`, `rules.rb:37`, `rules.rb:39`, `report.rb:14`.
- ID list: `rules.rb:9`, `dataset.rb:91`, `eval_runner.rb:117`, `evaluation_analysis.rb:7`, `script/evaluation_summary.rb:117`.
- Changing YAML changes `rules.revision`, so this is a benchmark-affecting change and must follow docs/evaluation.md freezing.

## Proposed Solutions

### Option 1: kind in YAML, Rules owns the list

**Approach:** Add `kind: tests|design` to each rule file, have Rules load every `*.yml` in the directory (or an explicit `ids` list), expose `Rules::IDS`/`rule['kind']`, and have Evaluator and Report dispatch on kind. The eval harness keeps its own expected-ID list because the dataset contract is fixed.

**Pros:**
- One source of truth
- Enables G5 or per-project rules

**Cons:**
- Changes rules revision; re-freeze needed

**Effort:** Medium (2-4 hours)

**Risk:** Medium

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/rules.rb`
- `lib/slop_guard/evaluator.rb:28`
- `lib/slop_guard/report.rb:14`
- `config/rules/*.yml`
- `config/rules/ruby/g3.yml`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No `%w[G1 G2]` kind literal outside Rules
- [ ] A fifth rule file loads without code changes in evaluator or report
- [ ] Saved benchmark definitions preserved and re-frozen per docs/evaluation.md
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
- Every rule file declares `kind`, plus `scenarios` (tests) or `candidate_kind` (design). Rules loads `*.yml` from the directory; Evaluator and Report dispatch on kind. Harness keeps `Rules::IDS` as the fixture contract.
