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

## Scoring

A true positive must match the rule, intended concern and an allowed source anchor. Wrong reasons/locations and duplicate accusations are false positives. An inconclusive answer on an answerable positive remains a miss in recall. Correct abstentions on intentionally incomplete cases and needless abstentions are separate counts. API failures fail completion and are reported separately from semantic accuracy. Raw readings remain available for inspection; the harness does not use another model to set ground truth.

Metrics include totals and counts per rule. Undefined precision/recall is `null`, not a perfect score. Repeat instability is reported from each full review, with no majority voting. This small dataset can qualify a controlled demonstration; it cannot establish general review accuracy.

## What is still unverified

- Live Jev judgments, calibrated thresholds and reproducible held-out outcomes.
- Actual GitHub installation, webhook lifecycle, comment locations and publication recovery.
- The planned hosted worker's persistence and restart behavior. The current reservation ledger covers local sessions only.
