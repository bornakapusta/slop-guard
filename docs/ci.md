# CI operation

## Required code-quality checks

Pull requests to `main` and pushes to `main` run on Ubuntu 24.04 with the pinned Ruby and Bundler versions. There are no path exclusions. Each job uses read-only repository permissions and no application secrets.

| Check | Local command | Policy |
|---|---|---|
| Tests | `COVERAGE=1 bundle exec rspec` | Failures block; coverage values do not |
| Static analysis | `bundle exec rubocop --except Metrics --cache false` | All enabled non-Metrics cops must pass |
| Dependencies | `bundle exec bundle-audit check --update` | Vulnerabilities and update/tool errors fail |
| Fixtures | `bundle exec ruby bin/evaluate --validate` | Structural validation only; deliberate incomplete contexts are valid |
| Complexity | `bundle exec rubocop --only Metrics --cache false` | Offenses are informational; execution/syntax errors fail the optional job |

The local Metrics command exits 1 for findings. CI accepts that only when a completed JSON report contains exclusively Metrics offenses. Complexity is not a required check.

SimpleCov starts before application code, reports lines and branches, and includes unloaded `lib/`, `script/` and `bin/` sources. Exec-based CLI subprocesses are not instrumented; their entry points remain in the denominator. Coverage has no minimum or drop threshold and does not establish feature-use-case adequacy.

Each job writes a summary and uploads allowlisted reports for 14 days. Tests include RSpec JSON and self-contained HTML/JSON coverage. Other jobs retain their JSON results. Available reports upload after ordinary failures. Runner loss, job termination or cancellation can prevent upload. New PR commits cancel obsolete ordinary CI runs.

## Main enforcement

The main ruleset requires pull requests and the observed GitHub Actions checks `Tests`, `Static analysis`, `Dependencies`, and `Fixtures`, with strict up-to-date checks, no mandatory reviewer count, and no bypass actors. Complexity and paid evaluation are excluded. These are GitHub settings, not properties guaranteed by workflow YAML. See the [checkpoint](verification/ci-checkpoint.md) for actual verification status.

## Paid development evaluation

After merging the workflow into the default branch, open Actions → Development evaluation → Run workflow, select `main`, or run:

```sh
gh workflow run evaluate.yml --ref main
```

Only manual dispatch is supported. Preflight rejects non-main refs before the paid job. The `jev-evaluation` environment independently allows only the branch `main`; it has no tag policy. Keep `TYPESAFE_API_KEY` only in that environment, with no repository-level duplicate. To rotate it, update Settings → Environments → jev-evaluation → Environment secrets. Never place a key in a workflow input or report.

The paid job checks out the dispatched commit, installs locked dependencies without restoring a cache, and runs:

```sh
bundle exec ruby bin/evaluate --live --split development --repeats 3
```

The key is available only to that step. Missing credentials fail before requests. The existing guard reserves at most $2 per invocation; each manual dispatch is a new budget session. Actual token-derived cost is distinct from conservative reservations. There is no monthly cap. One paid workflow runs at a time and a new dispatch does not cancel the active run; GitHub can replace older pending runs.

The evaluator step has 15 minutes inside a 20-minute job, leaving room for reporting after ordinary failure or step timeout. Completed cases are saved atomically. The summary shows exact completed case/repeat pairs, final per-rule counts and variability when available, label status, versions, token estimates and ledger reservations. Missing or malformed reports fail reporting; partial data cannot pass. Available `report.json`, `runs.jsonl` and `requests.jsonl` are retained for 14 days, including failed evaluations; the summary merges reviews finished after the last checkpoint from `runs.jsonl`. Download evidence you need to keep longer.

Neither this workflow nor green code-quality CI establishes model qualification. Follow [evaluation procedures](evaluation.md) for agreed labels, development calibration, freezing and held-out qualification. Historical evidence is preserved, but source/lockfile fingerprint changes require fresh evaluation before any new qualification claim.
