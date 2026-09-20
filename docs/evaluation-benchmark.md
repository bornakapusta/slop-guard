# Measuring reviewer quality and consistency

This adapts the fixed-input repeated-judgment experiment in [LangChain's Jev evaluation](https://www.langchain.com/blog/jev-agent-evals-langsmith) to Slop Guard's Ruby harness. The first version measures Jev alone. The existing 16 development cases are the fixed examples; each contains saved source, tests, a change and expected outcomes. Repeating them gives more observations of those same cases, not more independent examples.

## Run and inspect

Analyze an existing report without credentials or provider calls:

```sh
bundle exec ruby bin/analyze-evaluation tmp/evaluations/RUN/report.json
bundle exec ruby bin/analyze-evaluation tmp/evaluations/RUN/report.json --json > tmp/analysis.json
```

A readable report includes per-rule outcome agreement, repeat agreement, detected concerns, latency and cost. JSON adds confusion counts, finding precision/recall, per-case exact matches and per-question variance. Exit 0 means analysis succeeded, even if the reviewer performed badly. Invalid input exits 2. Use `bin/evaluate`'s exit status for evaluation pass/fail.

New ordinary evaluations collect the same measurements, with the existing default of 3 repetitions:

```sh
bundle exec ruby bin/evaluate --live --split development --repeats 3
```

For exploratory repeatability work, explicitly enable benchmark mode:

```sh
bundle exec ruby bin/evaluate --live --split development --benchmark --repeats 10
```

Benchmark mode accepts 1–100 repetitions, uses development cases only and stops after the first review with an operational failure. Ordinary runs remain limited to 1–3 repetitions; held-out qualification still requires 3. Benchmark reports cannot be frozen as qualification evidence.

The $2 reservation guard, per-review limits and request deadlines remain unchanged. A long run can exhaust that conservative budget before finishing; the report will show partial inventory and retain completed reviews. A new invocation starts a new budget session. Do not keep rerunning to get a favorable result. No larger budget is configured by benchmark mode.

Inputs and labels are loaded before repetition begins. No reviewed source is executed. Labels stay outside Jev's evidence. Each completed review is atomically saved, including monotonic wall-clock duration and question fingerprints. Provider failures remain separate from semantic mismatches. Model, rule, source, dataset, Ruby and lockfile versions remain in the raw report.

## What each measurement means

| Measurement | Definition and limit |
|---|---|
| Outcome agreement | Exact match to the expected G1–G4 outcome among reviews without operational failure. Includes `inconclusive` and `not_applicable`; frequent negatives can make it look high despite missed concerns. |
| Detected concerns / finding recall | Correct findings divided by expected findings. Matching requires rule, reason and allowed source anchor. An answerable violation marked inconclusive remains a miss. |
| Finding precision | Correct findings divided by all emitted findings. Wrong anchors and duplicate accusations are false positives. Undefined ratios are `null`. |
| Exact review match | All expected outcomes and findings match, with no extra findings. Observed provider failures count as non-matches in this rate. Missing reviews are reported in inventory rather than silently assumed successful. |
| Confusion counts | JSON rows are expected outcomes and columns are actual outcomes. Operational failures are excluded and counted separately. |
| Repeat agreement | Fraction of pairs of distinct observed repetitions that agree within a case, averaged equally across cases with at least 2 valid observations. `[concern, concern, inconclusive]` gives 1/3. A consistently wrong rule can score 100%. |
| Reading variance | Sample variance (`n-1` denominator) of each question's readings for one case. New reports group by the exact evidence/question fingerprint. Missing conditional questions are omitted, never filled with zeros; fewer than 2 samples gives `null`. This is not a rubric quality score or a calibration measurement. |
| Review latency | Mean and nearest-rank p50/p95 of the monotonic duration of the entire evaluator call, including multiple provider requests, retries and evaluator processing. Input preparation and report writes are excluded. Historical reports without per-review timing show unavailable values. |
| Cost | Sum of reported input tokens and their stored input-cost estimates; mean estimated cost per observed review. This is not a provider invoice or cost per API call. Request attempts include retries. |
| Reservations | Sum of reservations on saved review rows. An interruption during an unsaved review can leave additional reservations in `requests.jsonl`; that ledger remains authoritative. The CI summary separately reads the full ledger. |

Historical reports lack question fingerprints. Their variance keys start with `legacy-` and identify batch position plus question ID; interpret them only where those positions have the same meaning across repeats. The original raw report is never rewritten. The analysis records its version and source-report digest.

Partial reports describe only the completed observations and can be biased toward cases reached before interruption. Do not compare a partial subset with a complete benchmark as if both sampled the same examples. Small per-case sample counts and a small fixture corpus do not establish general accuracy.

## Human review is still needed

The current labels are provisional. Before treating agreement as human-oracle accuracy, a maintainer should inspect each development example's `change.diff`, `input.json`, full source/test evidence and `labels.json` against [the adopted guidelines](guidelines.md):

1. Confirm the promised behavior and whether G1–G4 apply, independently of the model's response.
2. For a violation, confirm the rule, concern and allowed source anchors. For a correction, verify the new assertion or design change actually resolves it.
3. Check legitimate lookalikes and incomplete context: an abstention can be the correct result, while an abstention on an answerable violation is a miss.
4. Resolve ambiguous labels, record the rationale, and add independent feature families as the corpus grows. More repetitions cannot substitute for this breadth.
5. Review held-out labels without using held-out model results to tune questions. Set `labels_reviewed` only after the required human review, then collect fresh same-version evidence.

`--freeze` rejects provisional labels and exploratory benchmark reports. No label, question or threshold was changed by adding these measurements. Source instrumentation changes the engine fingerprint, so old reports remain historical evidence.

The manual GitHub workflow still runs 3 ordinary repetitions. Its summary includes these metrics for new reports. No LangSmith account or additional provider is required; multi-model comparison remains a separate extension.

See [the historical example](verification/evaluation-benchmark.md) for a concrete report and [qualification procedure](evaluation.md) for the development/holdout gates.
