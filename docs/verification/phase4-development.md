# Phase 4 development check (2026-09-20)

One paid development evaluation (16 cases x 3 repetitions) run immediately after the Phase 4 prompt changes from
`docs/plans/2026-09-20-002-refactor-review-findings-remediation-plan.md`: evidence selection around the change,
one batched request per rule, scenario and candidate text moved from instructions into the untrusted state,
rule kinds declared in YAML, and a versioned report. Thresholds are the checked-in `high: 0.85`, `low: 0.20`.

This is a quality check, not a qualification run. Labels remain provisional (`labels_reviewed: false`), no lock
was frozen, and the engine changed again after the run, so this report cannot be replayed against current
versions without checking out commit `d8948ff`.

Operational result: 48 reviews, 0 operational
failures, 169 provider requests (0-5 per review,
down from up to 20), 96 seconds wall time, estimated input cost
$0.0756 against $0.4543 reserved.

Semantic result: no false positives, all 12 seeded violations missed,
67 unnecessary abstentions. The `incomplete` cases pass as
intended. Readings for the violations sit between the thresholds (for example G1 `clear` 0.82 and `missing`
0.78; G3 global `concern` 0.63), so the reviewer abstains rather than answering. G4's `applicable` reading is
0.13 on the seeded G4 violation, a disagreement with the label rather than a threshold problem. Threshold and
question tuning against development cases, followed by label review, remain the next evaluation steps; see
`docs/evaluation.md`.

# Slop Guard evaluation benchmark

Evidence: live provider responses.
Inventory: complete; 48/48 reviews, 16/16 distinct cases, 3 requested repetitions.
Labels: PROVISIONAL.
Operational failures: 0.
Exact matches among observed reviews: 12/48.

| Rule | Outcome matches / valid reviews | Outcome agreement | Repeat agreement | Detected concerns |
|---|---:|---:|---:|---:|
| G1 | 29/48 | 60.42% | 91.67% | 0/3 |
| G2 | 39/48 | 81.25% | 100.00% | 0/3 |
| G3 | 12/48 | 25.00% | 100.00% | 0/3 |
| G4 | 42/48 | 87.50% | 100.00% | 0/3 |

Review latency: 48 measured; mean 1.9941 s, p50 2.5508 s, p95 2.9392 s.
Input cost estimate: $0.075556; reservations in observed reviews: $0.454272.
Rule agreement excludes operational failures; exact matches include failed reviews as mismatches.
Repeat agreement averages within-case pairs. Stable answers can still be wrong.
Detected concerns match rule, reason and anchor; inspect misses and false positives.
JSON includes confusion counts, per-case results and conditional per-question sample variance.
Review latency includes all provider requests. Cost estimates are not actual charges.
Partial results describe only observed reviews. Repetitions do not add independent cases.
This report does not establish held-out qualification or human approval of provisional labels.

## Offline threshold replay of this run

`script/calibrate_thresholds.rb` replayed the saved readings from commit `d8948ff` (the engine at run time) over
the documented grid. Selection requires complete replay, zero false positives and preserved correct abstentions.
Full output: `phase4-threshold-replay.json`. Advisory only: the checked-in thresholds were not changed, and any
change needs fresh repeated development evaluations per `docs/evaluation.md`.

| Rule | Current high / low | Detected / unnecessary abstentions | Best replay high / low | Detected / false positives / unnecessary abstentions | Exact rule matches |
|---|---|---|---|---|---|
| G1 | 0.85 / 0.2 | 0 / 19 | 0.75 / 0.45 | 2 / 0 / 1 | 47/48 |
| G2 | 0.85 / 0.2 | 0 / 9 | 0.55 / 0.2 | 0 / 0 / 3 | 45/48 |
| G3 | 0.85 / 0.2 | 0 / 36 | 0.85 / 0.4 | 0 / 0 / 14 | 34/48 |
| G4 | 0.85 / 0.2 | 0 / 3 | 0.85 / 0.3 | 0 / 0 / 0 | 42/48 |

Only G1 would detect its seeded violation (2 of 3 repeats) at replayed thresholds; the other rules' readings on
their violations do not separate from the legitimate cases at any grid point without false positives.
