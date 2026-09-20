---
status: complete
priority: p2
issue_id: "011"
tags: [code-review, agent-native, architecture]
dependencies: []
---

# Report JSON has no format version, finding id or severity, and is undocumented

## Problem Statement

The report emits snapshot/version/model/rules_revision/status/rules/skipped_paths, where `version` is the engine version not the report format. Findings have rule/topic/anchor/readings/thresholds/message/correction/scenario but no severity and no stable id. The markdown renderer collapses G1/G2 duplicates for the same scenario and anchor but the JSON does not, so a bot would post duplicate inline comments. No document describes the JSON keys. G1/G2 anchors fall back to "first changed line of the first non-spec Ruby file", which is arbitrary for inline comments.

## Findings

- `lib/slop_guard/evaluator.rb:41-43` top-level keys; `evaluator.rb:161-163` finding keys.
- `lib/slop_guard/report.rb:14-21` dedupes in markdown only.
- `lib/slop_guard/snapshot.rb:71-74` arbitrary anchor fallback; rewritten on this branch with no spec.
- grep of docs/*.md finds no report schema.

## Proposed Solutions

### Option 1: report_version + finding id + schema doc

**Approach:** Add `report_version: 1`, `severity: 'advisory'`, a stable finding `id` (digest of rule+anchor+topic), explicit `anchor.side: 'head'`. Dedupe at the Evaluator/Review layer so JSON and markdown agree. Document keys in docs/report-schema.md (or a JSON Schema under config/). For G1/G2 anchors, prefer the changed candidate whose method the scenario names, else mark the finding as PR-level (no inline anchor) explicitly.

**Pros:**
- Idempotent comment updates for a bot
- Consumers can validate

**Cons:**
- Report shape change; analysis/summary validators must accept the new keys

**Effort:** Medium (half a day)

**Risk:** Low

## Recommended Action

**To be filled during triage.**

## Technical Details

**Affected files:**
- `lib/slop_guard/evaluator.rb:41-43,155-164`
- `lib/slop_guard/report.rb`
- `lib/slop_guard/snapshot.rb:66-75`
- `docs/`

## Resources

- **Branch:** `feat/local-repository-review`
- **Review:** whole-repo architecture/testing/Ruby-practices review, 2026-09-20
- **Project constraints:** `AGENTS.md`, `docs/local-repository-review.md`, `docs/evaluation.md`

## Acceptance Criteria

- [ ] Report carries `report_version` and each finding has `id` and `severity`
- [ ] JSON contains no duplicate findings for one scenario+anchor
- [ ] Anchor selection for test-coverage findings is specified and spec-covered
- [ ] Schema documented
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
- `report_version: 1`, finding `id` (digest of rule, topic, scenario, anchor path, matching the publisher), `severity: advisory`, `anchor.side: head`. Markdown dedupe removed so JSON and Markdown agree. Scenario anchors prefer the changed method the scenario names. Schema in docs/report-schema.md.
