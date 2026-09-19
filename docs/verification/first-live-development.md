# First live development evaluation

Run: 20260919T195144-20791. One pass over 16 development cases, using explicitly authorized TypeSafe requests. No held-out cases were queried.

| Measurement | Result |
|---|---|
| Exact case matches | 4 / 16; all four were omitted-context cases handled without model calls |
| Seeded guideline violations detected | 0 / 4 |
| False-positive findings | 0; no findings were emitted |
| Unnecessary inconclusive rule outcomes | 19 |
| Provider failures | 0 |
| Requests / reported input tokens | 62 / 646,409 |
| Estimated input cost | $0.02715; an estimate, not an invoice |
| Conservative reserved budget | $0.166656; not actual charges |
| Elapsed time | 61.19 seconds |
| Label review | Provisional; not yet maintainer-reviewed |

The configured API key and request/response contract worked. The current reviewer did not pass its development gate. Zero false positives is not evidence of usefulness when every seeded violation is missed. Repeat stability was not measured: this was one pass, so the report's zero outcome-flips count cannot establish consistency.

Specific development evidence:

- G1's missing-test example became inconclusive: clarity 0.82 and missing-coverage 0.62.
- G2 recognized missing failure coverage at 0.93, but clarity 0.81 fell below the experimental 0.85 gate.
- G3 returned inconclusive for all 12 answerable cases, including the seeded mixed-responsibility change.
- G4 classified its seeded abstraction example as not applicable at 0.19 applicability.

Next: inspect question wording and decision gates against these development examples, preserving the labels and this failed report. Do not simply lower thresholds until examples pass. Keep holdout untouched until development passes with frozen versions. GitHub implementation remains gated.

The adjacent JSON summary records version fingerprints and case outcomes. The full readings remain in ignored tmp/evaluations/20260919T195144-20791/report.json.
