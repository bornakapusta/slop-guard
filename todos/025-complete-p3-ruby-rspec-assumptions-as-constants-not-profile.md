---
status: complete
priority: p3
issue_id: "025"
tags: [code-review, architecture]
dependencies: [008]
---

# Ruby/RSpec assumptions are constants and string checks rather than a language profile

## Problem Statement

README calls this a general-purpose reviewer, but `spec/` prefix checks, `spec/spec_helper.rb` as a required file, `bin/`/`exe/` anchor eligibility and the KNOWN_REQUIRES whitelist are literals scattered across Candidates and Snapshot. There is no type that says "this is the Ruby/RSpec support boundary". Not urgent while Ruby-only; do it before a second language or test framework.

## Findings

- `candidates.rb:13` KNOWN_REQUIRES; `candidates.rb:48,56,65,69` and `snapshot.rb:50,72` `spec/` checks; `snapshot.rb:45` spec_helper requirement; `snapshot.rb:72` anchor path rules.

## Proposed Solutions

### Option 1: Language::Ruby object selected by profile

**Approach:** A `Language::Ruby` (or Profile methods `test_path?`, `known_requires`, `anchorable?`, `required_files`) consulted by Candidates and Snapshot.

**Pros:**
- Names the boundary
- Enables a second language cleanly

**Cons:**
- Premature if Ruby-only for long

**Effort:** Medium (2-3 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/candidates.rb`
- `lib/slop_guard/snapshot.rb:45,50,72`
- `config/repository.yml`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No `spec/` literal outside the language/profile object
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
- Profile carries the Ruby/RSpec conventions (test_path?, anchorable?, required_files, known_requires); Candidates and Snapshot consult it. A second language would supply its own Profile answers.
