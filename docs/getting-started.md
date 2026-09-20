# Getting started

Run commands from the Slop Guard checkout. The current evidence extractor supports small Ruby/RSpec projects.

## Install

Use Ruby 3.4. Activate `.ruby-version` with your Ruby manager; this checkout was tested with 3.4.5. Confirm `ruby -v` and `bundle exec ruby -v` use the intended interpreter. The Docker image targets a newer patched 3.4 release; see [GitHub App hosting](github-app.md).

```sh
bundle install
```

## Inspect an example offline

The README uses simplified payment API examples to explain the checks. The runnable cases below are separate log-parser fixtures; they are not recorded reviews of those README examples.

```sh
bundle exec ruby bin/review g2-violation --inspect
bundle exec ruby bin/review g2-fixed --inspect
```

The first case adds a documented error branch without a corresponding test. The second adds the assertion. Inspection prints JSON containing numbered source, test candidates, changed lines, selected rules, and evidence gaps. It makes no model requests, requires no API key, and produces no AI judgment.

The readable patches are [the violation](../eval/development/g2-violation/change.diff) and [the correction](../eval/development/g2-fixed/change.diff). Follow the [demo runbook](demo-runbook.md) for a guided walkthrough and historical results.

## Request a review from Jev

Copy `.env.example` to `.env` and set `TYPESAFE_API_KEY` locally. The file is ignored by Git. The CLI reads Slop Guard's credentials, not an environment file in the reviewed project.

```sh
bundle exec ruby bin/review g2-violation --live
```

This sends the selected source, tests, and change description to Jev and incurs provider usage. It does not execute the target project's code or tests. Use `--json` for a machine-readable response:

```sh
bundle exec ruby bin/review g2-violation --live --json
```

Each invocation makes a fresh review. It prints the report path on stderr and saves JSON under ignored `tmp/reviews/`.

The model is `jev-1.13.0`. Requests have bounded contexts, at most 20 attempts, and a 120-second review deadline. Conservative cost reservations cap a review at $0.10 and an evaluation session at $2 using the configured input-price estimate. Actual billing can differ. Each CLI invocation has a new ledger; these are not account-wide or monthly spending limits. The hosted App uses a shared persistent ledger with a separate operational lifecycle, documented in [App operations](github-app.md#retries-costs-and-operations).

The checked-in high/low thresholds are 0.85/0.20. The recorded G2 example used an experimental high threshold of 0.60; a new run with defaults need not reproduce that finding. See [calibration evidence](verification/threshold-calibration.md).

## Read the result

| Outcome | Meaning |
|---|---|
| `concern` | The rule's decision conditions support an advisory finding at a validated source location. |
| `no_concern` | The inspected evidence supports no concern for that rule or candidate. This is not proof of correctness. |
| `not_applicable` | The rule did not apply to the inspected change. |
| `inconclusive` | Missing evidence, ambiguity, conflicting readings, or an operational limit prevents a supported conclusion. |

A rule can retain a concern alongside unresolved evidence gaps. Read the gaps and overall status as well as the outcome. Reported model readings and decision thresholds are not review-accuracy percentages.

For `bin/review`, exit 0 means the review completed, even if it found concerns. Exit 2 means incomplete evidence, invalid input, or an operational failure. For `--inspect`, exit 0 only means evidence was constructed; inspect the reported gaps. Evaluation commands use exit 1 for expected-outcome mismatches and exit 2 for setup errors.

## Review your own repository

The target must contain committed base and head revisions. Write its expected behavior and failure cases using [this example](examples/review-expectations.md), then follow [local repository reviews](local-repository-review.md). That guide covers revision selection, supported files, custom questions, and evidence limits.

For automatic PR comments, register and host the [GitHub App](github-app.md). The App is a separate service; the reviewed repository does not need to install Slop Guard or run its dependencies.

## Check the implementation and evaluate review quality

```sh
bundle exec rspec
bundle exec rubocop --except Metrics --cache false
bundle exec ruby bin/evaluate --validate
```

These checks are offline and make no model requests. Validation covers 24 authored fixtures: 16 development examples and 8 held-out examples. Fixtures remain tracked under `eval/`; generated reports belong under `tmp/`.

Passing implementation tests does not qualify model accuracy. Follow [evaluation](evaluation.md) to assess questions against labeled cases and [evaluation benchmarks](evaluation-benchmark.md) to measure finding correctness and repeat consistency. [CI operations](ci.md) describes the automated checks and separate manual paid evaluation workflow.
