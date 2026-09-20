# Slop Guard

An experimental general-purpose code reviewer, implemented in Ruby, that asks Jev focused questions about code changes. Ruby selects evidence and decides which advisory findings to report.

The current evaluation dataset uses a Ruby log parser as a sample project. The reviewer is intended for use across projects; the CLI supports the supplied evaluation cases and committed changes in local Ruby/RSpec repositories.

**Current status:** local review engine and evaluation harness implemented. Experimental threshold calibration detected one of four seeded violations in three fresh development passes; the rules are not qualified and defaults remain unchanged. See [the calibration results](docs/verification/threshold-calibration.md). GitHub App delivery is the next phase, gated on successful evaluation.

The four rules assess observable behavior tests, relevant failure-case tests, focused responsibilities, and justified abstractions. Read [the adopted guidelines](docs/guidelines.md) and [the implementation plan](docs/plans/2026-09-19-001-feat-slop-guard-reviewer-plan.md).

## Demo: a new error case without a test

Use the [demo runbook](docs/demo-runbook.md) for setup, an offline walkthrough, and the commands for a fresh local or GitHub evaluation.

A change to the sample log parser makes `add_visit(nil)` raise an error:

```diff
 def add_visit(ip_address)
+  raise ArgumentError, "IP is required" if ip_address.nil?
+
   @visits_count += 1
```

The PR promises this failure behavior, but the existing tests only exercise valid input. Slop Guard's G2 rule checks whether any supplied test calls the relevant production code and asserts the promised failure outcome.

In three fresh development runs with experimental G2 thresholds (`high: 0.60`, `low: 0.20`), the reviewer reported this finding. The excerpt omits numeric readings and the other rules:

```text
G2: concern
lib/path_tracker/page.rb:17
The inspected tests do not assert this documented failure outcome.
Exercise the relevant invalid input through production code and assert its documented outcome.
```

The corrected example adds the missing assertion:

```ruby
RSpec.describe PathTracker::Page do
  it 'rejects missing IP' do
    expect { described_class.new('/home').add_visit(nil) }
      .to raise_error(ArgumentError, 'IP is required')
  end
end
```

G2 returned `no_concern` for the corrected example in all three runs. That result concerns the inspected evidence; Slop Guard does not execute the project's tests.

After local setup, inspect both saved examples without an API call:

```sh
bundle exec ruby bin/review g2-violation --inspect
bundle exec ruby bin/review g2-fixed --inspect
```

These commands print the review evidence. To request a fresh judgment, use `--live` as shown below. The checked-in thresholds are still `high: 0.85`, `low: 0.20`; they produced `inconclusive` for this violation in the first evaluation, so the live command is not guaranteed to reproduce the experimental finding. See the [violation patch](eval/development/g2-violation/change.diff), [corrected patch](eval/development/g2-fixed/change.diff), and [calibration report](docs/verification/threshold-calibration.md).

## Run locally

Use Ruby 3.4 (this checkout was tested with 3.4.5). Activate the version in `.ruby-version` with your Ruby manager first; `ruby -v` and `bundle exec ruby -v` must agree. Update to a maintained patched 3.4 release before deployment.

```sh
bundle install
bundle exec rspec
bundle exec rubocop --except Metrics --cache false
bundle exec ruby bin/evaluate --validate
bundle exec ruby bin/review g2-violation --inspect
```

Validation and inspection make no model requests. The supplied 24 cases include 16 development examples and 8 held-out examples. Every case has a readable `change.diff`, an `input.json` structured patch, and separate expected `labels.json`.

## Review another local repository

Run from the Slop Guard checkout with Ruby 3.4 activated. The target must be a local Git repository with the base and head commits available. This reviews committed changes from their merge base; staged, unstaged and untracked files are excluded.

Write a change description with `## Expected behavior` and `## Failure cases` sections. Use [the example](docs/examples/review-expectations.md) as a starting point and replace its scenarios with the behavior your change promises.

```sh
# Offline: inspect exactly which committed source and tests will be sent.
bundle exec ruby bin/review --repo /path/to/project \
  --base main --head HEAD --expectations /path/to/change.md --inspect

# Paid: send that evidence to Jev using Slop Guard's local API key.
bundle exec ruby bin/review --repo /path/to/project \
  --base main --head HEAD --expectations /path/to/change.md --live
```

Repository mode uses general Ruby responsibility questions; the saved log-parser benchmarks keep their original questions. Reports record the base, head, merge-base and rule revision. No GitHub token, webhook server or installation in the target repo is needed.

This is a bounded Ruby/RSpec reviewer, not a whole-repository audit. Source selection, custom rules, size limits and offline test behavior are explained in [local repository reviews](docs/local-repository-review.md).

## Review one case with Jev

Copy `.env.example` to `.env` and set `TYPESAFE_API_KEY` locally. Do not put credentials in a patch or paste them into a PR. The file is ignored by Git.

```sh
bundle exec ruby bin/review g2-violation --live
bundle exec ruby bin/review g2-violation --live --json
```

This makes paid requests. Requests use `jev-1.13.0`, bounded contexts, at most 20 attempts and a 120-second review deadline. Cost reservations cap each review at $0.10 and an evaluation session at $2 using the documented input price. Actual billing may differ; unknown usage retains its reservation. Reports are saved under ignored `tmp/`.

A concern does not fail the single-review command: exit 0 means the review completed, not that the code is correct. Exit 2 means invalid input, incomplete context, or an operational failure. Evaluation exits 1 for mismatched expected outcomes and 2 for setup errors.

## Evaluate quality before GitHub

Follow [the evaluation guide](docs/evaluation.md). The authored labels remain provisional until reviewed; development runs can help assess the questions, while qualification requires agreed outcomes. Tune only development cases, freeze the versions after a passing development run, then evaluate the held-out set three times. A passing mock response does not qualify a rule.

GitHub webhooks, inline comments, SQLite processing and deployment are not implemented yet. The reviewer and its planned GitHub App delivery remain separate from the projects it reviews; no reviewed application code runs inside the reviewer.

## CI and code quality

Pull requests and pushes to `main` run RSpec, non-Metrics RuboCop, dependency auditing and offline fixture validation. Coverage and complexity are informational. These checks test the reviewer implementation; they do not establish review accuracy or feature-use-case coverage.

A separate **Development evaluation** workflow runs Jev manually from `main`, with three development repetitions and the existing $2 reservation guard per run. Setup, local commands, reports and verification limits are in [the CI guide](docs/ci.md) and [the verification checkpoint](docs/verification/ci-checkpoint.md).

## Evaluate accuracy and repeatability

Analyze any saved evaluation without another API call:

```sh
bundle exec ruby bin/analyze-evaluation tmp/evaluations/RUN/report.json
```

The report separates label agreement, correct finding detection and repeat consistency, with latency and cost measurements for new runs. In the historical calibration run, G1 was 100% repeatable while detecting 0 of 3 repeated seeded violations. See the [benchmark guide](docs/evaluation-benchmark.md) for longer development runs, metric definitions and human label review.
