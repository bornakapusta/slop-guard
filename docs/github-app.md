# Run Slop Guard as a GitHub App

The App service is implemented in Ruby in this repository. One container runs Puma/Sinatra for webhooks and a separate Ruby worker. SQLite on a persistent local volume holds the delivery inbox, review checkpoints and publication IDs. GitHub hosts the App registration and PR conversation; your server hosts this container.

This version supports one configured installation and one Ruby/RSpec repository per deployment. It is experimental and advisory: the rules are not qualified, and it never approves, requests changes, or creates a required check. No target code, dependencies or tests run inside the service.

## What a PR receives

- Inline comments on supported changed lines, with the guideline, concern and suggested correction. These are grouped in a GitHub `COMMENT` review pinned to the reviewed commit.
- One summary comment with the finding count, descriptive check names, and plain-language explanations of unresolved checks. Every finding includes a link to its source line at the reviewed commit. Technical rule IDs, snapshot IDs and finding signals are in collapsed diagnostics. At most 20 inline comments are published per review; the summary retains all findings within GitHub's display limit, including those GitHub cannot place inline.
- Matching bot threads that GitHub still maps to the same path and line are updated. If a thread becomes outdated or its anchor moves, a new thread may be needed; historical threads are retained. Human comments and replies are untouched.

Example inline comment next to a new error branch:

> **Slop Guard · Failure case coverage** (advisory)
>
> **Code:** `lib/input.rb:12` (linked to the reviewed commit)
>
> **Context:** Missing input raises `ArgumentError`.
>
> The inspected tests do not assert this documented failure outcome.
>
> **Suggested change:** Exercise the relevant invalid input through production code and assert its documented outcome.

Unresolved checks are not findings and do not create inline accusations. A review with only uncertain judgments says “No actionable findings were reported” and “Some checks could not reach a conclusion.” It explains what needs manual review in the summary. This does not mean the change passed; finding quality still depends on the questions and supplied evidence.

That is an illustration of the format, not a guarantee the model will flag a particular change.

## Register and configure

1. Arrange an HTTPS endpoint for the service, for example `https://your-host.example/webhooks`. A VM with Docker and a reverse proxy works; a container hosting service must provide a persistent local disk and allow both processes to stay running. Run one replica. Do not put SQLite on shared network storage.
2. Create a GitHub App in your account or organization settings. Set the webhook URL above and generate a random webhook secret, for example with `openssl rand -hex 32`. Keep webhook SSL verification enabled.
3. Grant repository **Contents: Read-only** and **Pull requests: Read and write**. Metadata read access is implicit. Subscribe to **Pull request** events. Installation lifecycle events are handled as well. Checks permission is unnecessary for this version.
4. Generate the App private key and save the PEM outside the repository. Install the App on the selected demo repository. Record the App ID, installation ID, and repository ID. The installation ID is in the installation settings URL. Obtain the repository ID with `gh api repos/OWNER/REPO --jq .id`.
5. Copy `config/app.env.example` to `.env.app` and fill in its values. Use the same webhook secret as the registration. The file is ignored by Git. Starting the worker enables paid Jev calls for matching PR events, with the existing budget limits.

The repository allowlist uses numeric IDs, not webhook-supplied URLs. An installation token is scoped to that repository and the two permissions above. Rules and file patterns come from the deployed Slop Guard checkout, not from the reviewed PR.

## Start with Docker

```sh
cp config/app.env.example .env.app
# Fill .env.app, then set the host path to the downloaded App key.
export GITHUB_PRIVATE_KEY_FILE=/absolute/path/outside/repository/private-key.pem
docker compose up --build -d
curl --fail http://127.0.0.1:3000/healthz
docker compose logs -f slop-guard
```

The image runs as UID/GID 10001. Ensure the mounted private key is readable by that user using your host's file ownership or secret management. The key is mounted read-only and excluded from the image. Compose binds the HTTP port to loopback; configure your HTTPS reverse proxy to forward to port 3000 and limit request bodies to 1 MiB. The application also enforces this body limit.

The named `app-data` volume must survive rebuilds, updates and restarts. Back it up with SQLite's backup API or while the service is stopped, together with `budget.jsonl`. Do not use `docker compose down --volumes` for routine upgrades. Each data directory is bound to its App, installation and repository IDs; use a separate directory for another installation.

The Dockerfile targets Ruby 3.4.10. Local engine and service tests were run on Ruby 3.4.5. Container execution and live GitHub installation still require verification on the deployment host.

## Run directly with Ruby

With Ruby 3.4 active and `.env.app` configured:

```sh
bundle install
bundle exec ruby bin/app-server
```

The supervisor reads `.env.app`, starts the web process and worker, and stops both if either exits. `PORT` defaults to 3000. `SLOP_GUARD_DATA_DIR` defaults to ignored `tmp/app`. One worker holds an exclusive file lock for that directory. SIGTERM allows a short shutdown period; interrupted model work is reported as inconclusive on recovery, without repeating paid calls.

## PR expectations and evidence

Put `## Expected behavior` and `## Failure cases` sections in the PR body using [this example](examples/review-expectations.md). Missing or ambiguous requirements can produce `inconclusive` results. Events handled are opened, reopened, synchronize, edited, ready_for_review, converted_to_draft, and closed; the worker fetches the latest PR state and skips closed or draft PRs.

Source is read from GitHub trees and blobs at immutable head and merge-base commits. The inventory is checked against the complete PR file list, then the PR is fetched again to detect changes during collection. Limits include 50 changed files, 100 supported files per revision, 16 KiB per source file and PR body, 1 MiB combined source, and 120 seconds for source collection. Jev has its own tighter context and review budgets. Truncated inventories, unsupported source forms and missing RSpec setup cannot silently become a clean review. Fork PRs require those objects to be readable through the base repository's installation token; inaccessible objects produce an operational failure.

## Retries, costs and operations

Signed webhook deliveries are persisted before HTTP 202, and delivery IDs are deduplicated. Events for the same PR coalesce; the worker checks the latest PR and queue revision before each publication. GitHub can still accept a write during a concurrent push, so reviews always identify their commit. A detected race queues the latest state again.

Paid evaluation is checkpointed separately from publication. A publication retry reuses the saved report. A crash during evaluation does not restart its budget: the interrupted run becomes inconclusive. Each review retains the engine's 20-attempt, 120-second and $0.10 reservation caps. The persistent `budget.jsonl` adds a **$2 lifetime reservation cap for this deployment**, not a daily allowance. Actual billing can differ from reservations. When exhausted, reviews become inconclusive; stop the service and deliberately archive/rotate the ledger only when approving another spending allowance. Never rotate it merely to retry an interrupted review.

Every deploy that changes any file under `lib/`, `config/` or `Gemfile.lock` changes the engine revision, so each open pull request is re-evaluated once (one paid review) on its next event and receives a new inline review for the new run; its summary comment is updated in place.

Before a create request, the worker saves its intent. After an ambiguous response it looks for a bot-authored marker on GitHub. If delivery cannot be confirmed, it stops rather than blindly creating a duplicate. Definitive transient API failures retry up to four attempts and honor rate-limit delays. Logs contain job IDs, PR numbers, states and sanitized error descriptions. `/healthz` checks HTTP/storage availability; it does not prove GitHub or Jev connectivity or model quality.

Reports and publication intents are stored in `app.sqlite3`; failures are in `jobs.error`. There is no admin UI or automatic retention cleanup in this first version. Keep disk monitoring and backup in the hosting platform. Operator recovery for an uncertain write requires inspecting GitHub and the stored intent before requeueing; do not delete the database to force retries. Failed webhook deliveries must be redelivered through GitHub's delivery UI after an outage. Already acknowledged delivery IDs remain deduplicated.

Uninstalling, suspending, or removing the configured repository disables processing persistently. After restoring the installation, an operator must explicitly re-enable its `flags.enabled` value in SQLite, then queue a fresh event. Restarting alone does not undo a suspension. An incomplete review retains the previous complete review in the summary, so an outage does not silently clear earlier concerns.

## Validate before using a real repository

```sh
bundle exec rspec
bundle exec rubocop --except Metrics --cache false
bundle exec ruby bin/evaluate --validate
```

The service specs use fake GitHub/provider responses and temporary SQLite databases. They cover HMAC verification, repository restrictions, inline anchors, stale PRs, duplicate deliveries, lost create responses, interrupted evaluation and summary fallback. Offline tests establish implementation behavior; they do not establish live review quality.

For the first live check, use a disposable PR in the configured demo repository. Confirm a signed delivery returns 202, the summary names the current commit, supported findings appear inline, editing/pushing updates the review, and redelivery adds no duplicates. Inspect an incomplete case too. Live activation requires your App credentials, HTTPS host and a persistent volume.

API references: [webhook best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks), [App installation authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation), [pull request reviews](https://docs.github.com/en/rest/pulls/reviews), [review comments](https://docs.github.com/en/rest/pulls/comments), and [repository trees](https://docs.github.com/en/rest/git/trees). The client pins REST API version `2026-03-10`.
