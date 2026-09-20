---
title: Class-design cleanup — constructors, per-call objects, value objects, shared validation
type: refactor
status: active
date: 2026-09-20
---

# Class-design cleanup

Behaviour-preserving refactor of `lib/` against nine findings from the 2026-09-20 class review (rules: one verb per class, constructors only assign, one public `call`, private readers, `Data.define` values, no globals in default args, extend by adding classes, files == constants). Absorbs `todos/023` (Metrics hotspots), naming half of `todos/021`, spec seams from `todos/019`.

Keep: budget guards, read-only Git, trusted-rules/untrusted-evidence boundary, `config/rules/g*.yml` bytes, report JSON schema, exit codes, SQLite phases + publication intents.

## Governing constraints

- **Byte-identical outputs, not just equal.** `SlopGuard.digest` = SHA256(`JSON.generate`) → hash insertion order matters. Pinned: `rules_revision` (`rules.rb:47`), `snapshot.identity` (`snapshot.rb:21`, computed on RAW input before filtering), finding `id` (`evaluator.rb:227`, order rule/topic/scenario/path, `scenario` may be `nil` and stays), `question_fingerprints` (`evaluator.rb:85`, `[state, typed]`), candidate id (`candidates.rb:128`), scenario id (`expectations.rb:19`). Report keys: rule result `outcome, findings, gaps, readings, question_fingerprints[, error]` — `error` ABSENT unless set; finding `id, rule, severity, topic, anchor, readings, thresholds, message, correction, scenario`; anchor `path, line, side`. Gap ordering in `snapshot.rb:17-29,112-124` preserved.
- **String keys in memory.** `EvalRunner#score` (`runner.rb:47-55`), `Report.markdown`, CLI `--live` read the unserialised report. `Data#to_h` gives symbols → every finding scores false positive. Convert at Evaluator boundary with explicit string keys.
- **`versions.engine` / `Settings#engine_revision` change on every lib edit** — by design. No frozen lock exists; plan 002 Phase 6 not started. This plan must land BEFORE that freeze. Deploy note: worker re-keys open PR runs → one paid re-eval + second inline review per open PR.
- **Sequencing:** start after committing current uncommitted work on `refactor/profile-conventions` (threshold-calibration removal, todo cleanup). Ruby: `mise exec ruby@3.4.5 -- bundle exec …` (shell Ruby 4.0.1 breaks bundle).
- AGENTS.md: "introduce abstractions for present needs" → value objects only where they remove repeated `fetch` + Metrics offences (Rule, Finding, Anchor, RuleResult). No `Candidate` object unless Phase 2 shows need.

## Phase 0 — Goldens (no lib change)

- [x] `spec/fixtures/golden/`: `bin/review <case> --inspect` JSON for all 24 cases, `--show-rules` for `demo` + `ruby`, `bin/evaluate --validate` output, plus three deterministic `Evaluator#call` reports as JSON + Markdown. String compare. Generator `script/regenerate_goldens.rb`; renderer `spec/support/goldens.rb`; spec `spec/golden_spec.rb` (33 files, 832K).
- [x] Pin literal hex: `rules_revision` both profiles; g1-violation `snapshot.identity`; first `question_fingerprint` + finding `id` from `Goldens::FixedClient`. `spec/slop_guard/digests_spec.rb`.
- [x] Pin one full `Evaluator#call` report STRING per outcome (`concern`, `inconclusive`, `failed`+`error`) — as goldens `review/*.json`. Deep-walk no-Symbol-key spec and `error`-key-only-when-set spec in `digests_spec.rb`.
- [x] Assert `client.ask` receives the exact `state`/`typed` objects used for fingerprint (`digests_spec.rb`).
- [x] Baseline Metrics count: 234 offences in 43 files (main @ 22c4ceb, 2026-09-20).

Exit: goldens committed; suite green. Done: 207 examples, 0 failures; non-Metrics RuboCop clean.

## Phase 1 — Work out of constructors (rule 2)

Pattern already in repo: `Profile.load` vs `Profile.new`. Constructors assign only; a class method does the work.

- [x] `Snapshot.build(input, profile:)` → digests raw input FIRST, validates, filters, diffs, builds Expectations/Candidates, returns `Snapshot.new(files:, before:, changed:, identity:, gaps:, …)`. `snapshot.rb:9-30`. Callers: `cli.rb:112,120,123`, `github_source.rb:54`, `eval/runner.rb:134`, `bin/evaluate:34`, `spec/support/stub_client.rb:29`, `snapshot_spec.rb`, `git_source_spec.rb:92,110,246,260`.
- [x] Extract `Changes.diff(before, files)` (`snapshot.rb:129-141`) and `EvidenceSelection` (`selected_paths`/`state`, `snapshot.rb:39-72`) as own classes; `Snapshot#state` delegates. Key order of `state` untouched.
- [x] `Candidates.extract(files, profile:)` (`candidates.rb:17-36`); `Expectations.parse(body)` (`expectations.rb:8-25`).
- [x] `Rules.load(directory)` reads/validates; `Rules.new(definitions:, files:)` holds. Keep `Dir[]` order + `rescue` mapping (`rules.rb:16-31`). Callers: `cli.rb:31`, `worker.rb:13`, `rules_spec.rb`, `git_source_spec.rb:237-276`, `worker_spec.rb:61`.
- [x] `Budget.open(ledger:, …)` does `mkdir_p`; deadline still starts at open (`budget.rb:9-21`). Spec-flow #9: `.new` without `.open` must not exist on any path or `reserve!` raises `ENOENT` → wrong exit 2. Callers `cli.rb:159`, `worker.rb:99`, `runner.rb:139`.
- [x] `Store.open(path, identity:)` runs DDL + `bind` (`store.rb:9-32`); callers `bin/app-worker:10`, `spec/support/service.rb:8`, `store_spec.rb`.
- [x] `Settings.from_env(env)` reads key file + `mkdir_p` (`settings.rb:12-31`); callers `bin/app-server:10`, `bin/app-worker:7`.
- [x] Private `attr_reader` everywhere instead of bare ivars (JevClient `@api_key` done; RuleRun ivars go with the Phase 2 rewrite).

Exit: goldens byte-identical; `--inspect` on this repo identical except timing. Done: 207 examples green, all 33 goldens + pinned digests unchanged. Notes: `Trees`/`Changes`/`Evidence` live under `snapshot/`, `Candidates::Extractor` under `candidates/`; `Budget.new`/`Store.new` are private (only `open`); `Settings` is a `Data` subclass with `from_env` and an eager `engine_revision`. `Snapshot#initialize` takes 9 kwargs (one ParameterLists offence, accepted). Metrics total unchanged at 234.

## Phase 2 — Evaluator split + value objects (rules 3, 8, 11)

- [x] `Rule = Data.define(:id, :definition)` with `high?(v)`, `low?(v)` (`>=`/`<=`, `evaluator.rb:89-95`), `kind`, `tests?`, `[]`/`fetch` delegating to raw hash. `Rules#definitions` STILL returns raw hashes for `rules_revision`; `Rules#each_rule` yields `Rule`. `thresholds` = `definition.slice('high','low')`.
- [x] Move `Rules#validate!`/`validate_test_rule!`/`validate_design_rule!` (`rules.rb:50-83`) → `Rule.validate!(id, hash)`.
- [x] `RuleResult` (plain class, not Data — mutable during run): `concern!`, `no_concern!`, `inconclusive!(reason)`, `error!(msg)`, `<< reading`, `to_h` emitting exact key order, `error` key only when set. Replaces scattered `@result['outcome'] = …` (`evaluator.rb:47-51,73,84-86,222-240`).
- [x] `Finding = Data.define(:id, :rule, :severity, :topic, :anchor, :readings, :thresholds, :message, :correction, :scenario)`, `Anchor = Data.define(:path, :line, :side)`; `to_h` explicit string keys, order per Governing constraints. `Finding.id_for(rule:, topic:, scenario:, path:)` = existing digest. Publisher fallback `finding['id'] || …` (`publisher.rb:57-58`) stays for stored runs + `spec/support/service.rb:21-25` fixture.
- [x] `Evaluator::RuleRun` → `RuleRun` base (`call` guard order: empty diff+no gaps → not_applicable w/o ask; gaps → inconclusive w/o ask; rescue wraps whole call — `evaluator.rb:62-76`; `ask`, `concern`, `no_concern`, `inconclusive`) + `TestRuleRun` (`evaluate_tests`, `scenario_questions`, `classify_scenario`; only this one checks `expectations.gaps`) + `DesignRuleRun` (`evaluate_design`, `classify_candidate`, `classify_design`; keep `any_positive` comment for `g3.yml`). Files `lib/slop_guard/evaluator/rule_run.rb`, `test_rule_run.rb`, `design_rule_run.rb`. `Evaluator#call` picks class by `rule.tests?`; stop-after-first-error (`evaluator.rb:25`) unchanged.
- [x] Move `Rules#question` (`rules.rb:36-40`) → `JevClient::Question.typed(text)` (or `Questions` module beside client). Same `{'type','instructions'}` order, byte-identical suffix. `RuleRun#ask` still fingerprints the SAME `typed` hash it passes to `client.ask`. Update `rules_spec.rb:20`.

Exit: pinned report strings identical; `question_fingerprints` hex identical; `evaluator.rb` RuleRun ClassLength offence gone. Done: 208 examples green; goldens + digests unchanged. `Rule`, `Finding`, `Anchor` in `lib/slop_guard/{rule,finding}.rb`; `RuleResult`, `RuleRun`, `TestRuleRun`, `DesignRuleRun` under `evaluator/`; `Rules#all` yields `Rule`s, `Rules#question` → `JevClient::Question.typed`. Metrics 234 → 230.

## Phase 3 — Service per-call objects (rule 2 variant)

- [x] `Publisher#publish` → builds `Publication.new(client:, store:, number:, head:, run_id:, report:, changed:, current:).call`; kills ivars `publisher.rb:16-19`. `current.call` at same points (`publisher.rb:23,66,80,122`); `intend` before any create (`:81,:128`). Split `inline` (57 lines, CC 25): `existing_inline_review`, `inline_comments`, `post_inline_review`. Worker still constructs one `Publisher` (`worker.rb:12`); interface `publish(**)` unchanged for `worker_spec.rb`.
- [x] `GitHubSource#snapshot` → `TreeCollection.new(client:, profile:, base:, head:, ancestor:)` owning `@bytes/@gaps/@skipped/@blobs` (`github_source.rb:48-51`) — ONE object spanning both trees so blob cache is shared (spec-flow #11). `GitHubSource` keeps `pull`, `stamp`, `snapshot` public API for `worker_spec.rb` `instance_double`.
- [x] Spec: second `publish` via fresh per-call object with pre-`intend`ed key raises `PublicationUncertain` without `post`. Keep `worker_spec.rb:47-84` restart/phase cases.

Exit: `spec/slop_guard/service/*` green; `publisher.rb` no ivar assignment outside `initialize`. Done: 209 examples green. Publisher delegates to per-delivery `Publisher::InlineReview` and `Publisher::Summary` over a `Delivery` base (no intermediate Publication class — two verbs, two classes). `GitHubSource::TreeCollection` spans both trees so the blob cache is shared; `GitHubSource.sha` is a class method used by both. Spec added: publisher keeps only `@client`/`@store` after a publish.

## Phase 4 — Shared boundaries, split mixed classes (rules 1, 6, 7)

- [ ] `SourcePath.validate!(path, message:, control_chars: false)` — NOT unified semantics (spec-flow #8): GitSource keeps `[[:cntrl:]]` + 'Invalid Git tree path' (`git_source.rb:103-108`); Snapshot 'Unsafe source path' (`snapshot.rb:102`); Dataset 'Unsafe source path' (`dataset.rb:135-140`). Messages regex-matched in specs.
- [ ] `TextBlob.validate!(body, message:)` for `valid_encoding? && !include?("\0")` (`snapshot.rb:104`, `git_source.rb:131`, `github_source.rb:119-121`). Oversize policy stays per-adapter (gap vs `InputTooLarge`).
- [ ] `TreeEntryFilter` shared by `GitSource#tree` (`git_source.rb:60-90`) and `GitHubSource#tree`: submodule gap, permitted?, blob mode `%w[100644 100755]`, size cap. Parameterised by oversize handler. `skipped_paths` sort: GitSource sorts, GitHub doesn't — keep as-is (identity).
- [ ] `Budget` → `Deadline` (clock, `remaining`, `expired?`) + `Ledger` (file lock, `reserve!(amount)`, fail-closed parse) + thin `Budget` composing both, same public API (`reserve!`, `remaining`, `record_usage`, `attempts/usage/reserved` for `runner.rb:145-147`). `JevClient` depends on `deadline:` only where it reads `remaining` (`jev_client.rb:85,121,148,179`). Ledger line format `{"at","reserved_usd"}` unchanged (`script/evaluation_summary.rb:24`).
- [ ] `Report` → `Markdown` module (`escape`, `location`, `check_name`, `MENTION_BREAK`) + `Report` renderer. Callers `publisher.rb:99-102,141,147`, `eval/summary.rb:38,49`, `script/evaluation_summary.rb:35`, `report_spec.rb`. Renderer must not `fetch` `readings`/`report_version` (worker `incomplete` reports lack them — `worker.rb:104-108`, `report.rb:53` uses `[]`). Check U+200C stays visible as `"@‌"`; run `grep -rlP '[\x{2028}\x{2029}\x{200B}-\x{200D}]' lib` after edits.
- [ ] `CLI#build_snapshot` (`cli.rb:108-127`) → `Input::Git`, `Input::File`, `Input::Case` each `#input(pr_body:)`; CLI picks one. `GitSource` already fits.

Exit: goldens identical; no duplicated path/blob predicate (grep `include?("\0")` → 1 hit).

## Phase 5 — Namespaces, defaults, naming (rules 9, 14)

- [ ] `lib/slop_guard/eval/*` → `SlopGuard::Eval::Runner`, `Eval::Analysis`, `Eval::Summary`, `Eval::Dataset`. Callers: `bin/evaluate:29-30`, `bin/analyze-evaluation:21`, `script/evaluation_summary.rb:20,29,30`, `cli.rb:123`, `stub_client.rb:17`, `spec/eval/*`, `spec/ci/evaluation_summary_spec.rb:20`, `metrics_spec.rb`, `fixture_contract_spec.rb`. Closes `todos/021` naming item.
- [ ] Remove disk-reading defaults: `profile: Profile.load('ruby')` (`github_source.rb:11`, `worker.rb:8`), `rules: Rules.new` (`evaluator.rb:10`), `Eval::Runner` defaults (`runner.rb:27`). Callers pass explicitly: `bin/app-worker:14`, `bin/evaluate:30,34`, `evaluator_spec.rb` (8 sites), `design_rules_spec.rb:17`, `git_source_spec.rb:100,264`. Add `spec/support` helpers `demo_rules`/`ruby_rules`.
- [ ] `Rules::IDS` / `Analysis::RULES` / `Report::CHECK_NAMES` keep `%w[G1 G2 G3 G4]` (fixture contract).
- [ ] AGENTS.md structure section: new files, `.build/.load/.open` convention, per-call object rule, value-object boundary rule. `docs/report-schema.md` unchanged (verify). `docs/github-app.md` deploy note re engine_revision re-key.
- [ ] Metrics: re-run, record delta here. Target: RuleRun/Snapshot/Publisher/Budget/GitHubSource offences gone; remaining hotspots (`eval/analysis.rb#validate!`, `runner.rb#score`, `cli.rb#parse`) listed in `todos/023` update or new todo.

Exit: rspec, `rubocop --except Metrics`, `bin/evaluate --validate`, goldens all green.

## Acceptance criteria

- [ ] Goldens (Phase 0) byte-identical at every phase; pinned digests unchanged.
- [ ] No constructor in `lib/` performs IO, parsing, diffing or DDL (grep review).
- [ ] No ivar assigned outside `initialize` in `Publisher`, `GitHubSource`; `Evaluator` stateless.
- [ ] `Evaluator::RuleRun` replaced by `RuleRun`/`TestRuleRun`/`DesignRuleRun` ≤ 80 lines each.
- [ ] In-memory report has no Symbol keys (deep-walk spec).
- [ ] No default argument in `lib/` calls `Profile.load`, `Rules.load`, or reads disk.
- [ ] Every constant path matches file path (`SlopGuard::Eval::Runner` in `eval/runner.rb`).
- [ ] Metrics offences < 234 baseline; number recorded. Non-Metrics RuboCop clean.
- [ ] `todos/023` complete; `todos/021` naming item complete; new todo for leftover Metrics hotspots.
- [ ] Landed before plan 002 Phase 6 freeze; deploy note written.

## Risks

- Symbol-key leak scores silently wrong → Phase 0 deep-walk spec + string-compare goldens are the gate; do not use `eq(hash)`.
- Gap ordering shifts when moving Snapshot work into `build` → goldens include `gaps` for all 24 cases.
- Per-tree TreeCollection doubles GitHub blob fetches → one object spanning both trees.
- Renaming eval classes breaks `script/` + CI summary → grep before commit; `spec/ci/*` covers.
- Editing tool converts `\uXXXX` to literal chars → grep after Report/Markdown edits.
- Every phase changes `engine_revision`; no live run needed for this plan (no prompt/state change) — verify `question_fingerprints` hex unchanged instead.

## Sources

- Class review of `lib/` (this session, 2026-09-20) against api-main class rules.
- `docs/plans/2026-09-20-002-refactor-review-findings-remediation-plan.md` — governing freeze constraint, Phase 5 decisions, Metrics 199→243 unmet criterion.
- `todos/019`, `todos/021`, `todos/023`, `todos/029`.
- Digest sites: `lib/slop_guard.rb:38`, `rules.rb:47`, `snapshot.rb:21`, `evaluator.rb:85,227`, `candidates.rb:128`, `expectations.rb:19`, `eval/runner.rb:35-44`, `service/settings.rb:34-39`.
- Spec seams: `spec/support/stub_client.rb`, `spec/support/service.rb`, `spec/support/fake_connection.rb`.
- Conventions: `AGENTS.md`, `.rubocop.yml`, `docs/report-schema.md`, `docs/github-app.md:71-79`.

## Unresolved questions

1. `Candidate` value object too, or leave candidates as hashes (they are state rows sent to the provider; `to_h` order = `candidate_columns`)? Default: leave.
2. Phase 3 `Publication` per call: also make `Worker#process` phase machine its own `RunProcessor` object, or leave Worker as-is (121 lines, no per-call ivars)? Default: leave.
3. Goldens for all 24 cases (~24 JSON files, ~1–2 MB) vs a representative 6? Default: all 24, gitignored regeneration script.
4. Should `Budget` remain as a facade over `Deadline`+`Ledger`, or should CLI/Worker/Runner compose the two directly (changes 3 call sites + `runner.rb:145-147` reads)? Default: keep facade.
5. Land as one PR (as phases 2–5 of plan 002 were) or one PR per phase? Phase 0 separately is recommended regardless.
6. Update `todos/023` in place or close it and open `030-metrics-remaining` for `eval/analysis.rb#validate!`, `runner.rb#score`, `cli.rb#parse`?
