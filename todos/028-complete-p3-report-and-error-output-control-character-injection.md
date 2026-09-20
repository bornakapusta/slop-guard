---
status: complete
priority: p3
issue_id: "028"
tags: [code-review, security]
dependencies: []
---

# Report escaping and error messages let newlines and ANSI escapes through from reviewed repos

## Problem Statement

Report.escape neutralises Markdown punctuation but not `\n`, `\r` or ANSI escape sequences. Gap strings carry untrusted content: repository paths (GitSource only rejects absolute and `..` components, so `lib/evil\n## Injected\e[31m.rb` is accepted, confirmed) and `Missing fixture: #{fixture}` from spec source. Confirmed: a spec containing `File.read("fixture\n## Injected via fixture\n- fake")` yields a report with a forged heading and finding line. The same strings reach the terminal raw via `warn e.message`, allowing terminal escape injection from a reviewed repository.

## Findings

- `lib/slop_guard/report.rb:33-37` escape set lacks control characters.
- `lib/slop_guard/git_source.rb:55-58` path validation lacks a control-character check.
- `lib/slop_guard/candidates.rb:73` fixture path from source into gap text.
- `bin/review:71` prints messages raw.

## Proposed Solutions

### Option 1: Escape control characters and reject them in paths

**Approach:** In `escape`, replace `/[\u0000-\u001F\u007F\u0080-\u009F\u2028\u2029]/` with a visible placeholder or `inspect`-style escaping. In GitSource#tree reject paths matching `/[[:cntrl:]]/` as InvalidInput. Sanitise messages before `warn`.

**Pros:**
- Small, confirmed fix

**Cons:**


**Effort:** Small (1 hour)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/report.rb:33-37`
- `lib/slop_guard/git_source.rb:55-58`
- `bin/review:71`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Report spec with newline and ESC in a path shows escaped output, no forged heading
- [ ] GitSource rejects a tree path containing control characters
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options



### 2026-09-20 - Report half done

**By:** Claude Code (Phase 1, branch `fix/review-phase-1`)

**Actions:**
- `SlopGuard.printable(text, keep_newlines:)` renders C0/C1 controls and U+2028/U+2029 as visible escapes. `Report.escape` applies it last; all three bins pass error messages through it keeping deliberate newlines.
- Specs: a forged heading via gap text no longer produces a heading; a terminal message keeps its newline but escapes ESC.
- Remaining (Phase 2): reject control characters in Git tree paths at `git_source.rb:55-58`.


### 2026-09-20 - Fixed

**By:** Claude Code (Phases 2-5, branch `refactor/review-phases-2-6`)

**Actions:**
- Git tree paths containing control characters are rejected; report and terminal escaping landed in Phase 1.
