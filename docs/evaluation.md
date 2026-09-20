# Evaluating Slop Guard

The local engine, HTTP contract and harness can be tested without credentials. **Live qualification has not passed.** The [first development pass](verification/first-live-development.md) completed with valid provider responses but missed all four seeded violations. The dataset was authored before any model call; its rationales and expected outcomes still need maintainer review.

## Case format

`eval/manifest.json` defines IDs, split membership and feature families. Development cases cover a violation, legitimate lookalike, correction and incomplete context for each rule. Holdout families use different changes: aggregate totals, empty page paths, CSV collection output and visit ordering.

Each `input.json` names a baseline and maps changed paths to a preimage SHA-256 plus replacement content. `change.diff` is the human-readable view; JSON is the executable input contract. The loader verifies preimages and never invokes Git or a shell to apply a patch. `labels.json` contains all four expected rule outcomes, intended concerns, allowed anchors and rationale. Labels and split metadata do not enter the model state.

The source corpus includes full Ruby code and specs, including tests outside the diff and enclosing setup. The evaluator asks related questions together for each behavior or failure scenario. Design rules first ask about the whole context, then ask about individual candidates. A review therefore makes multiple sequential provider requests; oversized question sets are split further with the complete state repeated. Syntax candidates locate evidence; they do not decide whether a guideline is violated. Dynamic test generation, unresolved requires, omitted files and unsupported shared examples produce coverage gaps. This is a constrained Ruby demo, not a complete Ruby program analysis.

## Qualification sequence

1. Inspect development diffs and label rationales. Review holdout labels without using them to tune prompts. Resolve ambiguity from the guideline and feature contract. Set `labels_reviewed` to `true` in the manifest only after this review. Development runs may proceed with provisional labels, but the report preserves that status and cannot establish agreed review quality.
2. Provide `TYPESAFE_API_KEY` in the environment, or keep it in ignored `.env` and pass `--env-file .env`; the file is read only when named. Run development evaluation. Keep every failed report. Question wording and thresholds may change against development examples.
3. Once development passes, freeze its exact inputs. The lock records model, rules, engine, context profile, dataset, Ruby and gem lockfile fingerprints.
4. Run all eight held-out cases three times with fresh requests. Inspect raw results, unexpected findings, misses, abstentions, flips, probability ranges, cost and timing. All predetermined outcomes must pass before claiming qualified review behavior. The implemented GitHub App remains an experimental advisory pilot; its delivery tests do not satisfy this quality gate.
5. If holdout results inform tuning, move those families into development and author new held-out families before claiming a new pass. Update the fixed demo split contract deliberately if the dataset grows.

```sh
bundle exec ruby bin/evaluate --live --split development --repeats 3 --env-file .env
bundle exec ruby bin/evaluate --freeze tmp/evaluations/RUN/report.json
bundle exec ruby bin/evaluate --live --split holdout --repeats 3 --frozen tmp/frozen.json --env-file .env
```

Each invocation creates a new evaluation directory with `report.json`, a `runs.jsonl` line per finished review and a request-reservation ledger. `report.json` is checkpointed after each repetition and finalized at the end; interrupted sessions keep every finished review in `runs.jsonl`, which the CI summary merges back in, and conservative cost reservations. The `$2` session limit spans one `bin/evaluate` invocation; `bin/review` starts a fresh ledger per review and is bounded by its per-review limits only. There is no automatic resume or request-cache path; a new invocation starts a new explicitly requested session. Do not keep retrying a failed holdout until it happens to pass.

## Scoring

A true positive must match the rule, intended concern and an allowed source anchor. Wrong reasons/locations and duplicate accusations are false positives. An inconclusive answer on an answerable positive remains a miss in recall. Correct abstentions on intentionally incomplete cases and needless abstentions are separate counts. API failures fail completion and are reported separately from semantic accuracy. Raw readings remain available for inspection; the harness does not use another model to set ground truth.

Metrics include totals and counts per rule. Undefined precision/recall is `null`, not a perfect score. Repeat instability is reported from each full review, with no majority voting. This small dataset can qualify a controlled demonstration; it cannot establish general review accuracy.

## What is still unverified

- Reliable detection across all four rules, qualified thresholds and reproducible held-out outcomes.
- Actual GitHub installation, webhook lifecycle, comment locations and publication recovery.
- Hosted persistence and recovery under real deployment failures. The implemented SQLite worker has offline recovery tests and a persistent budget ledger; those checks do not establish live operational reliability. See [App operations](github-app.md).

## Manual evaluation in GitHub Actions

After the workflow is merged into `main`, dispatch **Development evaluation** from `main`. It runs the same development command above with three repetitions, using the `jev-evaluation` environment secret. It has no holdout or threshold inputs. Each dispatch starts a fresh budget session; the $2 reservation guard is not a monthly spending cap.

The job summary distinguishes a completed label match, mismatch, interrupted run and unavailable report. It reports provisional-label status, per-rule counts, repeat variability, versions, estimated input cost and request reservations. Download the raw report and ledger within 14 days. Code-quality CI and this workflow are independent; a green CI run is not model qualification. See [CI operation](ci.md).

The CI style cleanup and gem additions change version fingerprints. Earlier baseline and calibration reports remain historical evidence; they cannot freeze or qualify the new version. The offline threshold-replay tool that produced the calibration reports has been removed; threshold changes now require fresh repeated development evaluations. The 2026-09-20 remediation changed the prompts themselves (evidence selection, one batched request per rule, scenario and candidate text moved into the state), so `first-live-development`, `threshold-calibration` and `evaluation-benchmark` describe superseded prompts. The first run on the new prompts is [the Phase 4 development check](verification/phase4-development.md).

## Accuracy and repeatability reports

Use `bundle exec ruby bin/analyze-evaluation REPORT.json` to analyze saved evidence offline. Add `--json` for confusion matrices, per-case agreement, finding precision/recall and per-question sample variance. New reports include per-review latency. The [benchmark guide](evaluation-benchmark.md) documents the measurements, partial-run handling and the unchanged budget guard.

Freezing requires the report's labels to be marked reviewed; use a fresh development evaluation after label review.
