# Evaluating Slop Guard

The local engine, HTTP contract and harness can be tested without credentials. **Live qualification has not passed.** The [first development pass](verification/first-live-development.md) completed with valid provider responses but missed all four seeded violations. The dataset was authored before any model call; its rationales and expected outcomes still need maintainer review.

## Case format

`eval/manifest.json` defines IDs, split membership and feature families. Development cases cover a violation, legitimate lookalike, correction and incomplete context for each rule. Holdout families use different changes: aggregate totals, empty page paths, CSV collection output and visit ordering.

Each `input.json` names a baseline and maps changed paths to a preimage SHA-256 plus replacement content. `change.diff` is the human-readable view; JSON is the executable input contract. The loader verifies preimages and never invokes Git or a shell to apply a patch. `labels.json` contains all four expected rule outcomes, intended concerns, allowed anchors and rationale. Labels and split metadata do not enter the model state.

The source corpus includes full Ruby code and specs, including tests outside the diff and enclosing setup. Numbered evidence and syntax candidates fit bounded requests; larger question sets are batched with the complete state repeated. Dynamic test generation, unresolved requires, omitted files and unsupported shared examples produce coverage gaps. This is a constrained Ruby demo, not a complete Ruby program analysis.

## Qualification sequence

1. Inspect development diffs and label rationales. Review holdout labels without using them to tune prompts. Resolve ambiguity from the guideline and feature contract. Set `labels_reviewed` to `true` in the manifest only after this review. Development runs may proceed with provisional labels, but the report preserves that status and cannot establish agreed review quality.
2. Configure `TYPESAFE_API_KEY` in local `.env` and run development evaluation. Keep every failed report. Question wording and thresholds may change against development examples.
3. Once development passes, freeze its exact inputs. The lock records model, rules, engine, context profile, dataset, Ruby and gem lockfile fingerprints.
4. Run all eight held-out cases three times with fresh requests. Inspect raw results, unexpected findings, misses, abstentions, flips, probability ranges, cost and timing. All predetermined outcomes must pass before beginning GitHub integration.
5. If holdout results inform tuning, move those families into development and author new held-out families before claiming a new pass. Update the fixed demo split contract deliberately if the dataset grows.

```sh
bundle exec ruby bin/evaluate --live --split development --repeats 3
bundle exec ruby bin/evaluate --freeze tmp/evaluations/RUN/report.json
bundle exec ruby bin/evaluate --live --split holdout --repeats 3 --frozen tmp/frozen.json
```

Each invocation creates a new evaluation directory with `report.json` and a request-reservation ledger. Interrupted sessions retain the last complete case report and conservative cost reservations. There is no automatic resume or request-cache path; a new invocation starts a new explicitly requested session. Do not keep retrying a failed holdout until it happens to pass.

## Calibrating thresholds from saved readings

Run the offline sweep against a complete live **development** report from the current engine, rules and dataset:

```sh
ruby script/calibrate_thresholds.rb tmp/evaluations/RUN/report.json tmp/calibration/threshold-grid.json
```

This makes no API calls. It tests 90 high/low pairs per rule through the actual evaluator: high 0.50–0.95 and low 0.05–0.45, both in 0.05 steps. It first verifies version fingerprints and reproduces every original rule result exactly. Request replay matches the complete evidence and question text. If changed thresholds enter a branch whose questions were never recorded, that candidate is marked unavailable; no readings are invented.

Selection requires complete replay, zero false-positive findings and preserved correct abstentions. It then favors detected violations, exact rule matches, fewer unnecessary abstentions and smaller threshold changes, in that order. The output includes all candidates, original settings and the best replay settings. It does not modify the configured rules or qualify the reviewer. Fresh repeated development evaluations are needed to check whether an apparent improvement survives new model responses.

See [the first threshold calibration](verification/threshold-calibration.md) for the measured results and remaining blockers. These examples have provisional labels and only one seeded violation per rule, so fitted thresholds cannot establish general accuracy.

## Scoring

A true positive must match the rule, intended concern and an allowed source anchor. Wrong reasons/locations and duplicate accusations are false positives. An inconclusive answer on an answerable positive remains a miss in recall. Correct abstentions on intentionally incomplete cases and needless abstentions are separate counts. API failures fail completion and are reported separately from semantic accuracy. Raw readings remain available for inspection; the harness does not use another model to set ground truth.

Metrics include totals and counts per rule. Undefined precision/recall is `null`, not a perfect score. Repeat instability is reported from each full review, with no majority voting. This small dataset can qualify a controlled demonstration; it cannot establish general review accuracy.

## What is still unverified

- Reliable detection across all four rules, qualified thresholds and reproducible held-out outcomes.
- Actual GitHub installation, webhook lifecycle, comment locations and publication recovery.
- The planned hosted worker's persistence and restart behavior. The current reservation ledger covers local sessions only.

## Manual evaluation in GitHub Actions

After the workflow is merged into `main`, dispatch **Development evaluation** from `main`. It runs the same development command above with three repetitions, using the `jev-evaluation` environment secret. It has no holdout or threshold inputs. Each dispatch starts a fresh budget session; the $2 reservation guard is not a monthly spending cap.

The job summary distinguishes a completed label match, mismatch, interrupted run and unavailable report. It reports provisional-label status, per-rule counts, repeat variability, versions, estimated input cost and request reservations. Download the raw report and ledger within 14 days. Code-quality CI and this workflow are independent; a green CI run is not model qualification. See [CI operation](ci.md).

The CI style cleanup and gem additions change version fingerprints. Earlier baseline and calibration reports remain historical evidence; they cannot freeze or qualify the new version.
