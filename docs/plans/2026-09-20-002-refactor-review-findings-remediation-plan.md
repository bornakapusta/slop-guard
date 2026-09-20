---
title: Remediate whole-repo review findings and prepare the engine for GitHub bot use
type: refactor
status: active
date: 2026-09-20
---

# Review findings remediation

Fix the 29 findings in `todos/` (001–029) and reshape the seams so a GitHub PR adapter can reuse the engine. Keep: budget guards, read-only Git, trusted-rules/untrusted-evidence boundary, saved benchmark rule definitions in `config/rules/g*.yml`.

## Governing constraint: one freeze, at the end

`EvalRunner#versions` (`lib/slop_guard/eval_runner.rb:14-23`) fingerprints every `lib/**/*.rb`, `Gemfile.lock`, `config/demo.yml`, `eval/**/*.json` and rules. `freeze!` refuses any mismatch. So any lib change after a freeze invalidates it. Consequences:

- No lock exists today. `labels_reviewed: false` (`eval/manifest.json:174`), qualification never passed (`docs/evaluation.md:3`). Phase 3 destroys only exploratory evidence (`docs/verification/threshold-calibration.json` replay needs exact question text).
- Paid runs: one dev run after Phase 3 as prompt-quality check; final dev ×3 → `--freeze` → holdout ×3 after the LAST lib/lockfile/profile/dataset edit (end of Phase 6). Budget ≥2 paid dev cycles; expect tuning since first live run missed all seeded violations.
- Label review + flip `labels_reviewed: true` BEFORE the final dev run (changes `dataset` digest).

Fingerprint map:
- `rules_revision`: 007 (YAML). 008 only if YAML content changes.
- state shape / question fingerprints: 001, 026, 003.
- scored outcomes w/o fingerprint change: 011 (dedupe, anchors vs label anchors), 017 (abort-after-fatal → more `failed`), 003 (fewer LimitExceeded).
- `versions.engine`: every lib change. `lockfile`: 019 if rubocop-rspec added. `profile`: 008, 025. `dataset`: label flip.

## Phase 1 — Confirmed crashes and escaping (no prompt change)

- [x] 002 `Budget#reserve!` rescue `JSON::ParserError`/`KeyError`/`TypeError` → `InvalidInput 'Request ledger is corrupt'`; spec asserts no request sent (stub client). `lib/slop_guard/budget.rb:36`
- [x] 006 `Dataset#entry_for(id)` shared by `input`/`labels`, raises `InvalidInput`. `lib/slop_guard/dataset.rb:40-70`
- [x] 028 (report half) `Report.escape`: escape `[\u0000-\u001F\u007F\u0080-\u009F\u2028\u2029]` BEFORE the U+200C insertion; write U+200C as `"@\u200C"` with comment. Sanitise `warn` in `bin/review:71`, `bin/evaluate:70`, summary script. `lib/slop_guard/report.rb:33-37`
- [x] 005 `.env` opt-in: load only with `--env-file PATH` or `SLOP_GUARD_ENV_FILE`; missing file errors; document precedence env > file. `bin/review:57`, `bin/evaluate:57`, README, `docs/evaluation.md:16`
- [x] 021 (evaluator/report/jev/dataset parts) nested ternary → if/elsif; rename design booleans + comment that `any_positive` stays for `config/rules/g3.yml:14`; `ENDPOINT.freeze`; `dataset.rb:54` if/else; drop duplicate key check `bin/review:59`. Defer candidates.rb split to 023.
- [x] 019a Write `spec/slop_guard/rules_spec.rb` now (pins behaviour before 007/008): thresholds, unknown candidate ref, empty negative, `any_positive` optional, `repository:` swaps only G3, custom dir. Add `spec/support/stub_client.rb` (`instance_double(SlopGuard::JevClient)` + block) and `fixture_dataset` helper; migrate the three stubbing styles.

Exit: rspec, rubocop non-Metrics green. No paid run.

Done 2026-09-20 on branch `fix/review-phase-1` (worktree). 96 examples pass; lint clean. Also: `Rules` now maps missing rule files (`SystemCallError`) to `InvalidInput`; `.claude/worktrees/` gitignored. Tool note: the editing tool converts `\uXXXX` escape text into the literal character; check `grep -rlP '[\x{2028}\x{2029}\x{200B}-\x{200D}]'` after edits.

## Phase 2 — GitSource hardening (one PR, one pipe rewrite)

027 lists 016 as dependency; both rewrite `GitSource#git` (`lib/slop_guard/git_source.rb:89-125`). Do once.

- [x] 027 `Open3.popen3`; drain stderr concurrently with own byte cap; never merge into output; first stderr line (control chars stripped) in `InvalidInput` message. Spec: branch + tag both named `rel`.
- [x] 016 one `git cat-file --batch` per revision (stdin OIDs, parse `<oid> blob <size>`, handle `<oid> missing`); sizes from `ls-tree -l` enforce per-blob cap before read; env hash built once in constructor; replace `Timeout.timeout` with `IO.select`/deadline. Keep Ruby `fnmatch` filter after `ls-tree` (git pathspec `*.rb` semantics differ); pathspecs optional backstop only.
- [x] 028 (git half) reject tree paths matching `/[[:cntrl:]]/` at `git_source.rb:55-58`.
- [x] 029 (git parts) pass `-c protocol.allow=never -c core.fsmonitor=false`; `GIT_CEILING_DIRECTORIES` or `--show-toplevel` check for subdirectory `--repo`. Do NOT hard-refuse Git < 2.46 (ubuntu-24.04 CI image ships 2.43); warn + document.
- [x] 009 (GitSource part) `tree` returns `Data.define(:files, :gaps, :skipped)`; drop scratch ivars `git_source.rb:31-33`.
- [x] 019b GitSource specs: submodule gap, explicit `--head`, 100755 blob, output limit/timeout, 1 MiB bundle, `GIT_DIR` scrubbing, non-repo path, criss-cross merge base.

Exit: `bin/review --repo . --base main --inspect` output byte-identical to before (except timing). Constant git process count.

## Phase 3 — Structural seams (before facade; no prompt change)

Order matters: 012 → 008 → 004 → 010 → 022 → 024. 008 before 004 so the facade signature is final.

- [x] 012 Move `Dataset`, `EvalRunner`, `EvaluationAnalysis`, `EvaluationSummary` (from `script/`), `ThresholdCalibration` (from `script/`) → `lib/slop_guard/eval/`; `require 'slop_guard/eval'`; `lib/slop_guard.rb` engine-only; `Rules.from_definitions` replaces `SingleRule < Rules` + `super()`. Decide: `versions.engine` scoped to engine files or all lib (must be decided before final freeze). Keep `bin/evaluate --validate` path for CI (`ci.yml:152`). Update AGENTS.md structure.
- [x] 008 `SlopGuard::Profile` (file_patterns, limits, rules_dir) built once by CLI from YAML; passed to `GitSource`, `Snapshot` (required, always in identity), `Rules.new(profile.rules_dir)`. Demo profile `rules_dir = config/rules` (unchanged, preserves saved definitions); ruby profile `config/rules/ruby/` with copies of g1/g2/g4 + existing g3. Delete `repository:` kwarg and `bin/review:38-39`. One `Profile#permitted?(path)` replaces `snapshot.rb:35` + `git_source.rb:64`. Update `git_source_spec.rb:152-153,191`, `EvalRunner` default `Rules.new`, `versions['profile']` path. Demo snapshot identity changes (tmp reports only).
- [x] 004 `SlopGuard::Review.new(snapshot:, rules:, client:)` → complete report incl. `source` (from input hash; kills `bin/review:64`); `SlopGuard::CLI` owns parsing + inspect shape (`bin/review:50-55`, asserted by `git_source_spec.rb:152,191`). `bin/review` ≈ 10 lines. `cli_spec` in-process.
- [x] 010 One exit-code table for BOTH bins: 0 complete, 1 incomplete/label-mismatch, 2 usage/input, 3 provider/budget/operational; JSON error envelope under `--json` (incl. OptionParser errors); `--output DIR` / `SLOP_GUARD_OUTPUT_DIR`; `report_path`+`ledger_path` in JSON; narrow `SystemCallError` rescue so EACCES on output dir is reported correctly. Update `script/evaluation_summary.rb:11-23` (uses `exit_status.zero?`, 124 sentinel), `spec/ci/evaluation_summary_spec.rb`, `evaluate.yml:53-59`, README:102, `docs/local-repository-review.md:85,87`, `docs/evaluation-benchmark.md:14`.
- [x] 022 `InputTooLarge < InvalidInput` for size bounds (`git_source.rb:72,76,83`); decide ONE behaviour for >16 KiB file: Snapshot currently gaps (`snapshot.rb:29`), GitSource raises. Map to exit 2.
- [x] 014 (part) `JevClient::MAX_STATE_BYTES`, `MAX_REQUEST_BYTES`, `MAX_RESPONSE_BYTES`, `USD_PER_INPUT_TOKEN`; `Profile` fields for file/count/bundle/body bytes; keep `16_385` overflow sentinel at `bin/review:35`.
- [x] 024 `--expectations -` (stdin), `--input FILE` (document: bypasses preimage check, identity from raw input), `--show-rules` (definitions, revision, files used via Profile), resolved profile in `--inspect`.
- [x] 009 (Evaluator part) `evaluate_rule(id, rule, snapshot)` or `RuleRun`; `high?/low?` take rule; eager `'question_fingerprints' => []`; `client.model` on interface (`JevClient#model`, needed by `instance_double`).
- [x] 015 drop `rescue NoMethodError` (`dataset.rb:112`, `rules.rb:24`, `evaluation_analysis.rb:14`, `jev_client.rb:122`, summary script); add `is_a?` checks; `case/in` in `JevClient#validate` (guard non-Hash `answer`).
- [x] 020 keep a DOCUMENTED fallback for committed `docs/verification/*.json` (they lack `question_fingerprints`/`case_ids`), or mark them historical and remove analysis commands pointing at them. Remove `||=` origin via 009.

Exit: all specs green; `bin/evaluate --validate` unchanged output modulo identity.

## Phase 4 — Prompt-changing group (one paid dev run afterwards)

All of these change question fingerprints, `rules_revision` or scored outcomes. Land together, then ONE paid `bin/evaluate --live --split development --repeats 3` as quality check (not a freeze).

- [x] 001 Evidence selector between `Snapshot` and `state`: changed files + specs whose candidates reference changed methods/classes + `require_relative` closure (from `Candidates`); unchanged files as unnumbered path list; excluded files → gaps. Byte budget = `MAX_STATE_BYTES` minus headroom for the largest single question (client checks state + ONE question at `jev_client.rb:26`; 003's 56 KiB batching splits the rest). `bin/evaluate --validate` `state_bytes` will change; fix fixture spec assertions. Update bounds prose `docs/local-repository-review.md:93`.
- [x] 003 One `ask` per rule for all scenarios/candidates (namespaced IDs); sequential gate (`applicable`/`global`) stays a first call. Rework `evaluate_design` `next`/`return` flow (`evaluator.rb:128-153`) for batched values. `fingerprints.size == readings.size` must hold (`evaluation_analysis.rb:226-231`). Count real requests, not retries, toward `max_attempts`.
- [x] 026 Scenario/candidate text out of `instructions`: refer by ID; scenarios already in `state['pr']`, so prefer id-only (avoid duplicating text into 28 KiB cap). Strip control chars from candidate names. Spec: `instructions` contains only rule text + IDs.
- [x] 007 `kind: tests|design` in each YAML (changes `rules_revision`); `Rules` loads sorted `*.yml` non-recursively; `Evaluator`/`Report` dispatch on kind. Keep `%w[G1 G2 G3 G4]` in `Dataset#validate!`, `EvaluationAnalysis::RULES`, summary script as fixture contract.
- [x] 011 `report_version: 1`, `severity: 'advisory'`, finding `id` = digest(rule, anchor, topic) EXCLUDING readings; `anchor.side: 'head'`; dedupe G1/G2 in Evaluator so JSON == markdown. Anchor rule for G1/G2: changed candidate whose method the scenario names, else explicit PR-level finding — NOTE `EvalRunner#score` matches `finding['anchor']` against label anchors and counts duplicates as false positives; re-check every `labels.json`. `docs/report-schema.md`.
- [x] 017 Encode state once + running question byte count; one started `Net::HTTP` per client, close after 128 KiB abort, retry once on `EOFError`; backoff + injected RNG jitter capped at `budget.remaining`; drop outer `Timeout.timeout`; clamp timeouts `.clamp(0.001, …)` (029); inject `http:` factory so `post` is testable; Evaluator aborts remaining rules after fatal `ProviderError` (401/403 fatal; decide 400).
- [x] Docs: `docs/evaluation.md:11,61` note that first-live-development, threshold-calibration and evaluation-benchmark evidence is superseded by these prompts.
- [x] Paid dev run ×3; record under `docs/verification/`; tune thresholds/questions only against development cases.

Exit: dev run completes with status ≠ failed for all 16 cases; request count per review ≤ 2 + rules.

## Phase 5 — Eval pipeline and remaining cleanup

- [x] 013 `EvalRunner` records runs + passed/completed/seconds; `EvaluationAnalysis.new(result, case_ids:).to_h` computes metrics (keep `metrics.by_rule`, `outcome_flips` keys for `bin/evaluate:63` and CI summary); delete `probability_ranges`; `EvaluationSummary` delegates validation; one `ratio`/`nonnegative!` helper; split `run` into prepare/review_case/finalize.
- [x] 018 append `runs.jsonl` per run, `report.json` at end/every N; stop-on-failure still writes report; `analyze-evaluation` + summary accept it; `evaluate.yml:70-71` uploads `runs.jsonl`.
- [x] 014 (rest) remaining literals → constants.
- [x] 023 split `Snapshot#initialize` (`validate_tree!`, `apply_profile`), `Evaluator` decision procedures, `Dataset#validate!`, `Candidates#check_call` (+021 constants/helpers). Preserve gap ordering (`evaluator.rb:24` joins gaps).
- [x] 025 `Language::Ruby` / Profile methods `test_path?`, `known_requires`, `anchorable?`, `required_files`; behaviour byte-identical (gates `changed_candidates` `snapshot.rb:50` and anchor fallback `:72`; label shift otherwise).
- [x] 029 (rest) document session-ledger semantics at `docs/evaluation.md:57`; `chmod 600 .env` in README.
- [x] 019c remaining specs: `JevClient#post` via `http:` factory; split multi-behaviour examples (`cli_spec.rb:21-42`, `git_source_spec.rb:115-127`, `budget_spec.rb:14-23`); Evaluator branches (`evaluator.rb:72-76,94-96,124-127,133-138,155-159`, G2 path); Snapshot (`anchor` fallback, `changed_candidates`, >50 changed, `before_changed`); Expectations/Candidates/Budget boundaries. Optional rubocop-rspec (changes lockfile → before freeze).

Done 2026-09-20 on branch `refactor/review-phases-2-6`. Phases 2 to 5 landed as one branch (user decision: one PR at the end). Decisions taken on the open questions: `versions.engine` keeps covering all of `lib/` (Q1); a source file over 16 KiB is skipped with a gap in both adapters (Q2); a test-scenario finding anchors to the changed method the scenario names, else the first changed production line, and stays `inconclusive` with no anchor (Q3); any `ProviderError` stops the remaining rules (Q4); `--profile ruby|demo` is explicit, defaulting by mode (Q5); committed `docs/verification/*.json` stay readable through a documented fallback (Q6); one paid development run was authorized and made (Q7); rubocop-rspec was not adopted (Q8); `bin/review CASE_ID` keeps working and loads `slop_guard/eval` on demand (Q9). The GitHub App service was adapted to the new Profile, InputTooLarge and finding ids but not restructured. `SlopGuard::Review` was not added: `Evaluator` now emits `source` and `report_version` itself and `SlopGuard::CLI` owns composition, which covered 004 without a third class.

Phase 4 paid check: `docs/verification/phase4-development.md`. 48 reviews, 0 operational failures, 4 to 5 requests per review, 96 s, about $0.08 estimated. No false positives; all seeded violations still missed with the checked-in thresholds; an offline threshold replay is recorded alongside (advisory, thresholds unchanged).

## Phase 6 — Qualification

Not started: label review is the maintainer's, and the Phase 6 paid runs were not authorized in this pass.

- [ ] Maintainer label review; set `labels_reviewed: true`.
- [ ] Confirm no further lib/lockfile/profile/dataset edits pending.
- [ ] `bin/evaluate --live --split development --repeats 3` → passing → `--freeze` → `--live --split holdout --repeats 3 --frozen tmp/frozen.json`. Record in `docs/verification/`.

## Acceptance criteria

- [ ] All 29 todos renamed `complete` (or explicitly `wontfix` with reason). 25 complete; 019, 021, 023, 029 mostly done with notes.
- [x] `bin/review --repo <real repo> --base main --live` completes on a repository with >28 KiB permitted source. Verified offline: `--inspect` on this repository reports `fits_live_limit: true`; not exercised live (one paid run was authorized and spent on the development check).
- [x] Report has `report_version`, finding `id`, `severity`; JSON == markdown finding set.
- [x] Documented exit-code table shared by both bins; errors machine-readable under `--json`.
- [x] `require 'slop_guard'` loads no eval harness; no class definitions in `script/`.
- [x] No string from PR body or reviewed source in `instructions`.
- [x] Git: constant process count per revision, stderr never in data, control chars rejected.
- [x] Saved `config/rules/g*.yml` content unchanged except added `kind:`, `scenarios:` / `candidate_kind:` fields.
- [x] rspec (169), rubocop non-Metrics, `bin/evaluate --validate`, bundler-audit green. Coverage 78.8% → 85.3%.
- [ ] Metrics count reduced. NOT met: 199 offenses on main → 243 here. The single worst hotspots (`EvalRunner#run`, `Snapshot#initialize`, `Evaluator#evaluate_design`, `Dataset#validate!`) were split, but the new CLI, GitSource, Profile and Evaluator methods exceed the strict defaults (MethodLength 10, AbcSize 17). Informational in CI; follow-up in todo 023.
- [ ] Frozen lock + holdout evidence recorded. Phase 6 not started.

## Risks

- Phase 4 may need several tuning iterations; each dev run is paid. Cap: 3 dev cycles before revisiting rule design.
- 011 anchor changes can flip label matches silently; run `--validate` + offline replay after every anchor change.
- 016 batch protocol deadlock; mitigate with IO.select-based reader and spec on a 100-file repo.
- CI Git 2.43 vs local 2.49; lazy-fetch guard differs. Documented, not refused.

## Sources

- Findings: `todos/001-029` (whole-repo review, 2026-09-20; agents: architecture, security, performance, pattern/Ruby, simplicity, agent-native; spec-flow analysis for sequencing).
- Constraints: `AGENTS.md`, `docs/evaluation.md`, `docs/local-repository-review.md`, `docs/ci.md`.
- Fingerprint logic: `lib/slop_guard/eval_runner.rb:14-23,131-146`, `script/calibrate_thresholds.rb:118-120`.

## Unresolved questions

1. Should `versions.engine` cover only engine files after 012, or all lib including harness? (Decide before Phase 6.)
2. >16 KiB source file: gap (Snapshot today) or hard error (GitSource today)? One answer for 022.
3. G1/G2 anchor when no candidate matches: PR-level finding without anchor, or keep `inconclusive`? Affects labels and `EvalRunner#score`.
4. Is a fatal `ProviderError` on HTTP 400 (bad batch) or only 401/403? (017)
5. `--rules-dir` + ruby profile: explicit `--profile ruby|demo` flag, or profile inferred from `--repo`? (008)
6. Keep committed `docs/verification/*.json` readable via fallback, or mark historical and drop analysis commands? (020)
7. Budget for paid runs in Phase 4 and 6: how many dev cycles is the maintainer willing to pay for?
8. Adopt rubocop-rspec (lockfile change, new offences) in this plan or separately?
9. Move `bin/review CASE_ID` demo mode behind `slop_guard/eval`, or keep Dataset reachable from the product CLI?
