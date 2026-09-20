# Evaluation benchmark checkpoint — 2026-09-20

This is a new **offline analysis of existing historical evidence**, not a fresh model run. Source: `tmp/evaluations/20260919T200729-calibration/report.json`, the experimental threshold-calibration run documented in [the original checkpoint](threshold-calibration.md). Its thresholds and engine fingerprint differ from current defaults. No label or rule was changed. The [compact JSON](evaluation-benchmark.json) retains source hashes, recorded versions, confusion counts and key measurements.

## Historical results

Evidence: live provider responses.
Inventory: complete; 48/48 reviews, 16/16 distinct cases, 3 requested repetitions.
Labels: PROVISIONAL.
Operational failures: 0.
Exact matches among observed reviews: 31/48.

| Rule | Outcome matches / valid reviews | Outcome agreement | Repeat agreement | Detected concerns |
|---|---:|---:|---:|---:|
| G1 | 45/48 | 93.75% | 100.00% | 0/3 |
| G2 | 47/48 | 97.92% | 95.83% | 3/3 |
| G3 | 36/48 | 75.00% | 91.67% | 0/3 |
| G4 | 42/48 | 87.50% | 95.83% | 0/3 |

Review latency: 0 measured; mean unavailable s, p50 unavailable s, p95 unavailable s.
Input cost estimate: $0.081071; reservations in observed reviews: $0.497280.
Rule agreement excludes operational failures; exact matches include failed reviews as mismatches.
Repeat agreement averages within-case pairs. Stable answers can still be wrong.
Detected concerns match rule, reason and anchor; inspect misses and false positives.
JSON includes confusion counts, per-case results and conditional per-question sample variance.
Review latency includes all provider requests. Cost estimates are not actual charges.
Partial results describe only observed reviews. Repetitions do not add independent cases.
This report does not establish held-out qualification or human approval of provisional labels.

## Interpretation

G1's 93.75% outcome agreement and 100% repeat agreement coexist with **zero of three expected concern detections**. Its positive case is consistently missed. This illustrates why aggregate agreement or low variance alone cannot qualify the reviewer. G2 detects its seeded concern in all three repetitions; there is still only one positive case family for that rule.

The 31 exact matches out of 48 reviews represent 16 distinct development cases repeated three times. Labels remain provisional. These measurements do not establish general accuracy or held-out qualification. Historical per-review latency was not collected and is unavailable, rather than estimated from whole-run time.

## Implementation verification

73 RSpec examples pass. Non-Metrics RuboCop and offline validation of all 24 saved cases pass. No fresh hosted CI run is claimed for this separate local branch.

The new harness prepares inputs once, fingerprints exact question/evidence pairs and measures the full evaluator call with a monotonic clock. Explicit development benchmark mode supports up to 100 requested repeats with unchanged budget guards and stops on an operational failure. Ordinary CI remains at three repeats. The offline analysis command has no provider or dotenv dependency.

Behavior tests cover known-right, consistently wrong, unstable, correctly abstaining, unnecessarily abstaining, failed and partial observations; question identity; wrong finding anchors; repeat bounds; actual CLI behavior; timing; and qualification rejection for provisional labels or benchmark mode. The model request capture for all 24 saved cases matches the pre-change capture with fixed mock readings.

No new paid evaluation was performed. Human label review, a fresh current-version benchmark, model comparison and wider independent case families remain separate work. See [the benchmark guide](../evaluation-benchmark.md).
