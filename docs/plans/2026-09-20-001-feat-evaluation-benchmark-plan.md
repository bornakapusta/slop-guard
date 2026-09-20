---
title: Add repeatability and label-agreement evaluation reports
status: completed
date: 2026-09-20
---

# Evaluation benchmark

Adapt the fixed-input, repeated-judgment method from https://www.langchain.com/blog/jev-agent-evals-langsmith to the existing Ruby evaluator. Keep the existing saved cases and G1–G4 rules; do not change labels or claim human review.

- [x] Add an offline report for outcome agreement, confusion, exact-case matches, pairwise repeat agreement, reading variance, review latency and token-derived cost. Distinguish independent cases, repetitions, missing observations and operational failures.
- [x] Capture per-review timing and freeze the selected inputs in memory for repeated runs. Add an explicit development benchmark mode with up to 100 repetitions; ordinary CI remains at three and existing budget guards remain intact. Stop benchmarks after an operational failure and retain partial evidence.
- [x] Exercise scoring with known-right, consistently-wrong, unstable, abstaining, failed and partial results. Test repeat boundaries and the actual CLI. Render historical evidence offline without claiming new live performance.
- [x] Document human label review, local commands, statistical limits and the distinction between a review and a provider call. Run RSpec and non-Metrics RuboCop and review the final diff.

The implemented first version targets Jev; no multi-model comparison was added. No new paid run is required to implement and validate the harness.

Verification: 73 RSpec examples pass; non-Metrics RuboCop and all 24 fixture validations pass. Historical analysis is recorded in `docs/verification/evaluation-benchmark.md`. Human label review and a fresh current-version paid benchmark remain explicitly outside this implementation checkpoint.
