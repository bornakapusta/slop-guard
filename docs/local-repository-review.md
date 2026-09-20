# Local repository reviews

Slop Guard can read a local Git repository and run the same review engine used by saved evaluation cases. It needs neither a GitHub App nor a GitHub token. `--inspect` is offline; `--live` sends selected source, tests and the supplied change description to Jev and incurs provider usage.

## Run a review

1. In the target repository, commit the change on a feature branch. Keep a base branch or commit available locally. If you downloaded a ZIP, first establish a Git baseline and then commit the intended change; a directory alone has no revisions to compare.
2. Write a Markdown file describing the change's expected behavior and failure cases. Copy [the example](examples/review-expectations.md) and replace its scenarios. Missing expected behavior prevents a complete test-coverage verdict; an empty failure section does not prove there are no relevant failures.
3. From Slop Guard, with Ruby 3.4 activated, inspect the evidence:

```sh
bundle exec ruby bin/review --repo /absolute/path/to/project \
  --base main --head HEAD --expectations /absolute/path/to/change.md --inspect
```

`--head` defaults to `HEAD`. `--base` and `--expectations` are required. Revisions are resolved to immutable commit IDs once; the comparison is `merge-base(base, head)` to `head`, as for a feature PR. Base-only commits are excluded. This does not fetch, switch branches, modify the index, install target dependencies or execute target code. Working-tree edits are excluded even if the target is dirty.

Inspection prints JSON with numbered source, changed lines, test candidates, skipped paths, context bytes, evidence gaps, rule revision and Git commit IDs. Inspect mode exits 0 when evidence can be constructed, even when it reports gaps; exit 2 means invalid input or exceeded limits. No AI verdict is produced by inspection.

4. To request a model judgment, set `TYPESAFE_API_KEY` in the environment or keep it in Slop Guard's ignored `.env` and add `--env-file .env`, then replace `--inspect` with `--live`. The file is never read unless named. Add `--json` for JSON instead of Markdown. The report location is printed on stderr and JSON is saved under Slop Guard's ignored `tmp/reviews/` directory. Reports include the exact Git revisions and rule revision. A completed review exits 0 even when concerns are found; incomplete evidence and operational failures exit 2.

## Supported evidence and questions

The trusted `config/repository.yml` selects Ruby files under `lib/`, `app/` and `spec/`, root-level Ruby files, files directly under `bin/` and `exe/`, text/log fixtures under `spec/fixtures/`, and `.rspec`. Other paths appear in `skipped_paths` and are not sent as source. This profile is for small Ruby/RSpec projects. `spec/spec_helper.rb` is required; unsupported dynamic examples, unavailable dependencies or missing fixtures produce incomplete evidence. Broad Rails support and other test frameworks are not established.

All selected files at both revisions are available as context. Renames are represented by the before and after trees. Symlinks and submodules are not followed and produce explicit coverage gaps. Binary or invalid UTF-8 source is rejected. Initial bounds are 100 supported files per revision, 16 KiB per source file, 1 MiB for both source trees, 16 KiB for the expectation text and 50 changed supported paths. Git commands have a 10-second timeout and bounded output. The Jev client's tighter context/question limits still apply; a large inspected bundle can therefore be refused by live review without truncating evidence. Git 2.49.0 was used for verification; partial-clone lazy fetching is disabled.

G1, G2 and G4 reuse the existing questions. Repository mode substitutes `config/rules/ruby/g3.yml` for the log-parser-specific G3 rule. It asks about unrelated responsibilities and concrete adverse consequences without referring to log parsing. Neither this general profile nor the demo profile is qualified for reliable review accuracy.

For explicit project-specific questions, prepare a trusted directory outside the proposed change containing `g1.yml`, `g2.yml`, `g3.yml` and `g4.yml` with the existing schema, then pass `--rules-dir /path/to/trusted-rules`. This replaces all four definitions, including G3. The program does not automatically load configuration from the target repo. Thresholds and question changes need separate evaluation; custom questions do not automatically gain benchmark evidence.

## Test offline

```sh
bundle exec rspec spec/slop_guard/git_source_spec.rb
bundle exec rspec
bundle exec ruby bin/evaluate --validate
```

The Git adapter specs create temporary repositories, commit before/after versions, inspect actual Git objects and pass the resulting snapshot through the existing evaluator with stubbed Jev responses. They cover merge-base semantics, dirty working trees, additions/deletions/renames, unsupported files, unsafe inputs and CLI inspection. They do not need credentials or network access and do not establish model accuracy.

For future GitHub API adapters, recorded HTTP responses are another option: [Octokit uses VCR for API fixtures](https://github.com/octokit/octokit.rb), and [VCR records and replays HTTP interactions](https://github.com/vcr/vcr). Recordings must exclude credentials. A webhook forwarded from GitHub to a local server is a separate online integration test, as described in [GitHub's webhook testing guide](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/testing-webhooks). No webhook receiver or comment publisher is included in this local mode.
