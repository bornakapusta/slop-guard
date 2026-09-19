# Slop Guard

An experimental Ruby reviewer that asks Jev focused questions about changes to a small log parser. Ruby selects evidence and decides which advisory findings to report.

**Current status:** local review engine and evaluation harness implemented. The first live development run missed all four seeded violations; the rules are not qualified. See [the results](docs/verification/first-live-development.md). GitHub App delivery is the next phase, gated on successful evaluation.

The four rules assess observable behavior tests, relevant failure-case tests, focused responsibilities, and justified abstractions. Read [the adopted guidelines](docs/guidelines.md) and [the implementation plan](docs/plans/2026-09-19-001-feat-slop-guard-reviewer-plan.md).

## Run locally

Use Ruby 3.4 (this checkout was tested with 3.4.5). Activate the version in `.ruby-version` with your Ruby manager first; `ruby -v` and `bundle exec ruby -v` must agree. Update to a maintained patched 3.4 release before deployment.

```sh
bundle install
bundle exec rspec
bundle exec rubocop --lint --cache false
bundle exec ruby bin/evaluate --validate
bundle exec ruby bin/review g1-violation --inspect
```

Validation and inspection make no model requests. The supplied 24 cases include 16 development examples and 8 held-out examples. Every case has a readable `change.diff`, an `input.json` structured patch, and separate expected `labels.json`.

## Review one case with Jev

Copy `.env.example` to `.env` and set `TYPESAFE_API_KEY` locally. Do not put credentials in a patch or paste them into a PR. The file is ignored by Git.

```sh
bundle exec ruby bin/review g1-violation --live
bundle exec ruby bin/review g1-violation --live --json
```

This makes paid requests. Requests use `jev-1.13.0`, bounded contexts, at most 20 attempts and a 120-second review deadline. Cost reservations cap each review at $0.10 and an evaluation session at $2 using the documented input price. Actual billing may differ; unknown usage retains its reservation. Reports are saved under ignored `tmp/`.

A concern does not fail the single-review command: exit 0 means the review completed, not that the code is correct. Exit 2 means invalid input, incomplete context, or an operational failure. Evaluation exits 1 for mismatched expected outcomes and 2 for setup errors.

## Evaluate quality before GitHub

Follow [the evaluation guide](docs/evaluation.md). The authored labels remain provisional until reviewed; development runs can help assess the questions, while qualification requires agreed outcomes. Tune only development cases, freeze the versions after a passing development run, then evaluate the held-out set three times. A passing mock response does not qualify a rule.

GitHub webhooks, inline comments, SQLite processing and deployment are not implemented yet. CI/CD and the GitHub App remain separate from the log-parser application; no application code runs inside the reviewer.
