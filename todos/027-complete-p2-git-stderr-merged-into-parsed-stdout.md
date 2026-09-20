---
status: complete
priority: p2
issue_id: "027"
tags: [code-review, security, reliability]
dependencies: [016]
---

# GitSource merges Git stderr into stdout and treats it as data

## Problem Statement

GitSource#git uses Open3.popen2e, so any Git warning is concatenated into the parsed result. Confirmed: a branch and a tag both named `rel` make rev-parse print "warning: refname 'rel' is ambiguous" into the SHA output, and the review fails with a misleading "Local Git merge-base failed". Worse in principle: a warning during `cat-file blob` would be silently appended to reviewed source text, numbered as evidence and sent to Jev with no error (not triggerable on git 2.49 in probing, so theoretical).

## Findings

- `lib/slop_guard/git_source.rb:96` `Open3.popen2e`.
- `lib/slop_guard/git_source.rb:79` cat-file output becomes file body unvalidated beyond UTF-8/NUL.

## Proposed Solutions

### Option 1: popen3 with bounded stderr drain

**Approach:** Switch to Open3.popen3, drain stderr separately with its own byte cap, never mix it into `output`, and include the first stderr line (control characters stripped) in the InvalidInput message.

**Pros:**
- Correct data, clearer errors

**Cons:**
- Must read both pipes without deadlock (use IO.select or a thread)

**Effort:** Small (1-2 hours)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/git_source.rb:89-125`
- `spec/slop_guard/git_source_spec.rb`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Ambiguous ref produces an InvalidInput naming the ambiguity
- [ ] Git warnings never appear in file bodies
- [ ] Spec with a branch/tag name collision
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
- Open3.popen3 with stderr drained under the same deadline and capped; the first stderr line (control characters escaped) is included in the InvalidInput message. Spec: branch and tag both named rel.
