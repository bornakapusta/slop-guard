---
status: complete
priority: p2
issue_id: "008"
tags: [code-review, architecture]
dependencies: []
---

# Configuration is loaded from disk inside library classes; Rules `repository:` flag ignores its directory argument

## Problem Statement

GitSource loads config/repository.yml in its constructor, Snapshot loads config/demo.yml when no profile is given, and Rules defaults to ROOT/config/rules. Rules.new(directory, repository: true) always reaches into config/rules/ruby/g3.yml regardless of `directory`, and bin/review encodes the decision as `repository: !options.key?(:rules)`, so `--rules-dir` silently disables the Ruby profile. A Git adapter knowing about file_patterns is a mixed concern, and a bot cannot inject per-installation config. Identity is also computed differently depending on whether a profile was passed.

## Findings

- `lib/slop_guard/git_source.rb:15` loads the profile; `git_source.rb:64` filters by it.
- `lib/slop_guard/snapshot.rb:33-35` digests `[input, profile]` or `input` and defaults to demo.yml.
- `lib/slop_guard/rules.rb:8-14` `repository:` special case; `bin/review:38-39` derives it from option presence.
- Profile glob matching is duplicated at `snapshot.rb:35` and `git_source.rb:64`.

## Proposed Solutions

### Option 1: Profile value object plus rules directory per profile

**Approach:** Introduce `SlopGuard::Profile` (file_patterns, limits, rules_dir) constructed once by the CLI/bot from a YAML path and passed to GitSource, Snapshot and Rules. Make Snapshot require a profile and always include it in identity. Replace `repository:` with `Rules.new(profile.rules_dir)` where config/rules/demo/ holds the saved benchmark definitions and config/rules/ruby/ holds copies of g1/g2/g4 plus the general g3.

**Pros:**
- Library becomes injectable
- Removes the special case and the duplicated glob check
- Saved benchmark definitions preserved

**Cons:**
- Touches CLI, three classes and docs
- Demo identity changes (tmp reports only)

**Effort:** Medium (half a day)

**Risk:** Medium

---

### Option 2: Minimal: overrides kwarg

**Approach:** Replace `repository:` with `overrides: { 'G3' => path }` or `profile: :ruby`, honour `directory`, and document exclusivity with `--rules-dir`.

**Pros:**
- Small

**Cons:**
- Config still loaded inside library classes

**Effort:** Small (1 hour)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/git_source.rb:11-19,64`
- `lib/slop_guard/snapshot.rb:33-39`
- `lib/slop_guard/rules.rb:8-26`
- `bin/review:36-39`
- `config/repository.yml`
- `config/demo.yml`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] No library class reads a config path from ROOT by default
- [ ] `--rules-dir` behaviour with the Ruby profile is explicit and documented
- [ ] One shared `permitted?(profile, path)` helper
- [ ] Snapshot identity always includes the resolved profile
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
- `SlopGuard::Profile` (name, file_patterns, rules_dir, Ruby/RSpec conventions) is built by the CLI, GitHub App or harness and passed to GitSource, GitHubSource, Snapshot, Candidates and Rules. `--profile ruby|demo`; ruby rules live in config/rules/ruby with G1/G2/G4 copies. Snapshot identity always includes the profile.
