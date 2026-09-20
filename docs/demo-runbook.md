# Slop Guard demo runbook

Slop Guard is a general-purpose code reviewer implemented in Ruby. This demo uses saved changes to a Ruby log parser to show evidence selection, advisory review, and evaluation reporting. The current CLI accepts saved cases; GitHub App review comments are not implemented.

## Prepare locally

Start from the repository root on the merged `main` branch. Activate Ruby 3.4.5 from `.ruby-version`. With mise, prefix commands as below; with another Ruby manager, activate that version and omit the prefix.

```sh
git status --short --branch
mise exec ruby@3.4.5 -- ruby -v
mise exec ruby@3.4.5 -- bundle check
mise exec ruby@3.4.5 -- bundle exec ruby bin/evaluate --validate
```

If dependencies are missing, run `mise exec ruby@3.4.5 -- bundle install`. Validation should accept all 24 fixtures. `labels_reviewed: false` and `live_qualified: false` describe the current evaluation status.

## Walk through the example without API calls

1. Show the promised error behavior and its missing test:

   ```sh
   cat eval/development/g2-violation/change.diff
   mise exec ruby@3.4.5 -- bundle exec ruby bin/review g2-violation --inspect
   ```

2. Show the correction and the evidence now available to the reviewer:

   ```sh
   cat eval/development/g2-fixed/change.diff
   mise exec ruby@3.4.5 -- bundle exec ruby bin/review g2-fixed --inspect
   ```

3. Open [the recorded calibration result](verification/threshold-calibration.md) and [its benchmark analysis](verification/evaluation-benchmark.md). Identify these as historical live evidence using experimental thresholds. Inspection itself does not ask Jev for a judgment or execute the sample project's tests.

Explain the distinction between outcome agreement, correctly located findings, and repeat consistency. A consistently missed violation can produce perfect repeat consistency.

## Request fresh local judgments

For live requests, configure `TYPESAFE_API_KEY` in ignored `.env` using `.env.example`. Keep the value out of terminal output and presentation material.

```sh
mise exec ruby@3.4.5 -- bundle exec ruby bin/review g2-violation --live
mise exec ruby@3.4.5 -- bundle exec ruby bin/review g2-fixed --live
```

Each command makes paid requests with a $0.10 reservation limit, at most 20 attempts, and a 120-second review deadline. Reports and reservation ledgers are saved under `tmp/reviews/`. Exit 0 means the review completed; exit 2 means invalid input, incomplete evidence, or an operational failure.

The committed thresholds remain `high: 0.85`, `low: 0.20`. The historical G2 finding used experimental `high: 0.60`; a fresh run with defaults may be inconclusive. Present the actual outcome and any gaps. The rules have not passed qualification.

## Run the development evaluation on GitHub

After `main` CI passes, dispatch the manual workflow once:

```sh
gh workflow run evaluate.yml --ref main
gh run list --workflow evaluate.yml --branch main --limit 5
```

Use the ID of that dispatch in the following commands, replacing `RUN_ID`:

```sh
gh run watch RUN_ID --exit-status
gh run view RUN_ID --web
gh run download RUN_ID --dir tmp/demo/github-RUN_ID
```

The `jev-evaluation` environment supplies the key. This paid run requests 16 development cases three times, with a $2 session reservation limit. Inspect the job summary and download its report and ledger; artifacts expire after 14 days. A failed evaluation can still provide useful evidence: distinguish semantic mismatches from provider or setup failures. Do not rerun just to obtain a passing result.

Analyze the downloaded `report.json` offline, substituting its actual path:

```sh
mise exec ruby@3.4.5 -- bundle exec ruby bin/analyze-evaluation path/to/report.json
```

The equivalent local evaluation command is `mise exec ruby@3.4.5 -- bundle exec ruby bin/evaluate --live --split development --repeats 3`; it prints the report path. Evaluation exit 1 denotes expected-outcome mismatches, and exit 2 denotes setup errors. Keep development evaluation separate from held-out qualification; follow [the evaluation guide](evaluation.md) before making qualification claims.
