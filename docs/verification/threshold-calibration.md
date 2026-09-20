# Threshold calibration, 2026-09-19

Threshold changes improved development results but did not qualify the reviewer. **Configured defaults remain high 0.85 / low 0.20 for all four rules.** Candidate thresholds were loaded separately for the experiment; question text, decision logic and labels were unchanged. Holdout cases were not evaluated or used to select thresholds.

## Offline experiment

Replayed the saved first live development pass through the production evaluator. Before sweeping, all original rule results were reproduced exactly. Version checks cover the engine, rules, dataset, model, profile, Ruby and dependency lockfile; requests match the complete evidence and question text.

The fixed grid contained 90 pairs per rule (360 total): high 0.50–0.95 and low 0.05–0.45, in 0.05 steps. Forty-five G3 pairs required questions absent from the original recording and were excluded from selection. Missing readings were never inferred. All selected pairs were fully replayable, emitted zero false-positive findings and preserved the four expected incomplete-context abstentions per rule. Ranking then favored true positives, exact rule matches, fewer unnecessary abstentions and less threshold movement.

| Rule | Candidate high | Candidate low | Exact rule matches, saved readings |
|---|---:|---:|---:|
| G1 | 0.75 | 0.20 | 14/16 → 15/16 |
| G2 | 0.60 | 0.20 | 14/16 → 16/16 |
| G3 | 0.85 | 0.35 | 4/16 → 13/16 |
| G4 | 0.85 | 0.40 | 12/16 → 14/16 |

Combined candidate outcomes matched 11/16 saved cases, detecting only G2's seeded violation. These fitted results are not fresh evidence.

## Fresh validation

Ran all 16 development cases three times using the selected settings, with normal request budgets and no answer reuse.

| Run | Exact case matches | Seeded violations detected | False-positive findings | Unnecessary inconclusive outcomes |
|---|---:|---:|---:|---:|
| Original settings, first live pass | 4/16 | 0/4 | 0 | 19 |
| Fresh candidate pass 1 | 10/16 | 1/4 | 0 | 6 |
| Fresh candidate pass 2 | 11/16 | 1/4 | 0 | 5 |
| Fresh candidate pass 3 | 10/16 | 1/4 | 0 | 6 |

Across repeats, 4 cases changed their outcome vector. G2 matched its expected rule outcome on 47/48 reviews. The provider reported 0 operational failures. The comparison is one original pass versus three fresh candidate passes, not a paired repeated baseline experiment.

The fresh trial used 185 requests and 1,930,253 input tokens: approximately $0.08107 estimated input cost, with $0.497280 conservatively reserved. Reservations are not charges. Elapsed time was 184.41 seconds.

## Why thresholds alone are insufficient

- **G1, feature tests:** the saved violation needs high ≤ 0.62 to accept missing coverage, but low ≥ 0.71 to reject every existing test as coverage. Those constraints contradict the required low < high. The global and individual-test judgments disagree.
- **G2, failure tests:** the saved violation has missing coverage 0.93 and clarity 0.81. Its legitimate control has clarity 0.61. High 0.60 / low 0.20 resolves both in replay; this is an experimental decision cutoff, not evidence of 60% review accuracy.
- **G3, responsibilities:** the saved violation has global concern 0.64 and local justification 0.69. Flagging it requires high ≤ 0.64 and low ≥ 0.69, again impossible with shared ordered thresholds.
- **G4, abstraction:** the saved violation's applicability is 0.19. No tested high threshold can admit it as applicable. Increasing low mostly turns uncertainty into “not applicable,” which does not establish that the rule can recognize unjustified abstraction.

The candidate set still fails the development gate, so it was not promoted or frozen. The next useful work is to reconcile applicability, coverage and justification questions with concrete evidence, then repeat development calibration. No holdout run or GitHub integration was started. Labels remain provisional, with only one seeded violation per rule; this small fixture cannot establish general review accuracy.

## Reproduction and checks

```sh
ruby script/calibrate_thresholds.rb tmp/evaluations/20260919T195144-20791/report.json tmp/calibration/threshold-grid.json
```

The complete sweep, candidate YAML files and full live readings remain in ignored `tmp/`. The adjacent JSON preserves settings, version fingerprints, per-repeat metrics, per-case replay outcomes and changed outcomes across fresh repeats.

Validation: 47 RSpec examples passed; Ruby lint inspected 28 files with no offenses. Six new examples guard against held-out input, stale versions, partial datasets, mismatched questions, changed evidence and unrecorded decision branches.
