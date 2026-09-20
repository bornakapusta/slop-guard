---
status: pending
priority: p2
issue_id: "016"
tags: [code-review, performance]
dependencies: []
---

# GitSource spawns one cat-file per blob and lists the whole tree before filtering

## Problem Statement

GitSource runs one `git cat-file blob` subprocess per selected file per revision, up to 200 processes for two 100-file trees, each rebuilding the environment hash and paying a Timeout thread. Measured: about 0.7 s of a 1.2 s inspection on this repository (31 files). `ls-tree -r --full-tree` lists the entire tree with no pathspecs, so a monorepo with tens of thousands of files hits the 4 MiB output limit and reports "Local Git output exceeds its byte limit" instead of the intended 100-file message. Fine at current scale; matters for a bot on real repositories.

## Findings

- `lib/slop_guard/git_source.rb:78-79` per-blob `git('cat-file', 'blob', oid, limit: 16_384)`.
- `lib/slop_guard/git_source.rb:51` `ls-tree -r -l -z --full-tree revision` without `--` pathspecs.
- `lib/slop_guard/git_source.rb:91` environment hash rebuilt per call.
- `Timeout.timeout` around `readpartial` (`git_source.rb:100`) is unsafe if this code ever runs in threads.

## Proposed Solutions

### Option 1: cat-file --batch and pathspecs

**Approach:** One `git cat-file --batch` per revision, feeding OIDs on stdin and parsing `<oid> blob <size>` headers (sizes from ls-tree still enforce the per-blob limit before reading). Pass profile globs as pathspecs after `--` to ls-tree; keep the 4 MiB backstop. Build the environment once in the constructor. Replace Timeout with `IO.select`/`wait_readable` deadlines.

**Pros:**
- ~2 processes instead of ~200
- Correct error on huge monorepos
- Thread-safe

**Cons:**
- Batch protocol parsing needs careful specs

**Effort:** Medium (3-4 hours)

**Risk:** Medium

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/git_source.rb:50-125`
- `spec/slop_guard/git_source_spec.rb`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Reading a 100-file revision spawns a constant number of git processes
- [ ] A tree with many unsupported files reports the file-count limit, not the byte limit
- [ ] Existing git_source specs pass
- [ ] `bundle exec rspec` and `bundle exec rubocop --except Metrics --cache false` pass

## Work Log

### 2026-09-20 - Initial Discovery

**By:** Claude Code (multi-agent code review)

**Actions:**
- Finding surfaced by review agents and verified against source (file:line references above)
- Drafted solution options


