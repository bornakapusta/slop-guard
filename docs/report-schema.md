# Review report schema

`bin/review --live --json` prints the report below plus `report_path` and `ledger_path`. The same object is
saved as `report.json` and stored by the GitHub App service. `report_version` changes only when a key is renamed,
removed or changes meaning; additions keep the version.

## Top level

| Key | Type | Meaning |
|---|---|---|
| `report_version` | integer | Schema version, currently `1`. |
| `snapshot` | string | SHA-256 of the review input and the resolved profile. Two reviews of identical evidence share it. |
| `version` | string | Slop Guard engine version. |
| `model` | string | Provider model identifier the client reports. |
| `rules_revision` | string | SHA-256 of the loaded rule definitions. |
| `status` | `complete` / `incomplete` / `failed` | `incomplete`: at least one rule has evidence gaps. `failed`: a provider or budget error stopped the review; later rules were not attempted. |
| `rules` | object | One entry per rule ID (`G1`..`G4` for the shipped profiles). |
| `skipped_paths` | array of strings | Files present in the trees but outside the profile's `file_patterns`. Never sent to the model. |
| `source` | object | Provenance from the adapter, e.g. `kind`, `base`, `head`, `merge_base` for local Git. Empty for saved cases. |

## Per rule

| Key | Type | Meaning |
|---|---|---|
| `outcome` | `not_applicable` / `no_concern` / `concern` / `inconclusive` | Advisory verdict. `concern` always has at least one finding. |
| `findings` | array | See below. |
| `gaps` | array of strings | Why the rule could not reach a verdict, or why parts of the evidence were unavailable. |
| `readings` | array of objects | Raw provider probabilities per request, keyed by question ID. Not certainty scores. |
| `question_fingerprints` | array of strings | SHA-256 of `[state, questions]` per request, one per entry in `readings`. |
| `error` | string, optional | Present only on `failed` reviews. |

## Finding

| Key | Type | Meaning |
|---|---|---|
| `id` | string | SHA-256 of rule, topic, scenario and anchor path. Stable across repeats and readings, so a publisher can update a comment instead of duplicating it. |
| `rule` | string | Rule ID. |
| `severity` | `advisory` | Every finding is advisory; the reviewer never blocks. |
| `topic` | string | Scenario ID for test rules, candidate name for design rules. |
| `scenario` | string or null | Scenario text for test rules. |
| `anchor` | object | `path`, `line` (1-based, in the head revision) and `side: "head"`. The line is always a changed line. |
| `message` | string | The rule's message. |
| `correction` | string | The rule's suggested correction. |
| `readings` | object | The probabilities this finding was derived from. |
| `thresholds` | object | `high` and `low` in force. |

## Exit codes

| Code | `bin/review` | `bin/evaluate` |
|---|---|---|
| 0 | Review completed (concerns may be present). | All expected outcomes matched. |
| 1 | Review completed with incomplete evidence; the report is still valid. | At least one expected outcome mismatched. |
| 2 | Usage error, invalid input, input too large, or unreadable trusted configuration. | Same. |
| 3 | Provider, budget or deadline failure. | Not used; provider failures are recorded per case. |

With `--json`, an error prints `{"error": {"class", "message", "exit_status"}}` on stdout and nothing else.

## Inspect output

`bin/review --inspect` prints `snapshot`, `gaps`, `expectation_gaps`, `skipped_paths`, `source`, `profile`,
`rules_revision`, `rules_files`, `state_bytes`, `live_limit_bytes`, `fits_live_limit` and the full `evidence`
state that a live review would send. `--show-rules` prints `profile`, `rules_revision`, `rules_files` and the
loaded `definitions`.
