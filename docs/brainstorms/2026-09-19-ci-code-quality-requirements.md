---
date: 2026-09-19
topic: ci-code-quality
---

# CI and Code Quality for Slop Guard

## Problem Frame

Contributors currently run Slop Guard's checks locally. The inspected checkout has RSpec, RuboCop and evaluation validation, but no CI workflows. Pull requests need consistent, visible checks for the reviewer's own code. A successful code-quality run must not imply that Jev's judgments are qualified.

The user selected a practical CI baseline. Deployment was explicitly deferred after discussing full CI/CD. Slop Guard remains a general-purpose reviewer; the bundled sample project is its current evaluation fixture.

## Requirements

**Required pull-request checks**

- R1. Use GitHub Actions to run tests, static analysis, formatting/style checks, dependency security checks and offline fixture validation on pull requests and pushes to the default branch. Required checks must finish with explicit results, including on fork pull requests, without a TypeSafe key or paid model calls. A failed check or tool/setup error must not be represented as success.
- R2. Use the existing RSpec suite and RuboCop, adding bundler-audit for vulnerable dependencies and insecure gem sources. Enforce lint and agreed non-metric formatting/style rules. Clean the initial non-metric baseline as part of implementation, preserving behavior. Keep Metrics enabled in the informational report. Do not blanket-suppress rules in the required profile or exclude production files merely to obtain a green run. Any individual exception needs an explanation in configuration or documentation.
- R3. Run the existing offline evaluation validator. Preserve the authored evaluation fixtures and labels, including intentionally deficient source examples. Fixture source stays outside the reviewer's style/coverage checks, while the validation and evaluator code remains in scope. CI must not rewrite fixtures, labels, questions or thresholds to satisfy a check.

**Informational quality measurements**

- R4. Add SimpleCov coverage reports and report RuboCop complexity/size findings. Neither a coverage percentage nor a metric offense blocks merging in this phase. Coverage must include relevant reviewer code that tests never load; fixture/demo code and vendored/generated files must not inflate the result. Missing or failed report generation must be visibly distinguishable from a clean report. A test failure still fails the required test check even when coverage collection is incomplete.
- R5. Make results available in the workflow summary and downloadable artifacts. Required check names must be stable enough for branch protection. Document equivalent local commands and how to read required versus informational results. Prevent merging with failed required checks where repository settings permit; verify enforcement or explicitly document the remaining administrator step rather than claiming workflow YAML alone enforces it.

**Separate live evaluation**

- R6. Provide a manually triggered live development-evaluation workflow, separate from required PR checks. Reuse the existing evaluator, three repetitions and its request/deadline guards, including the $2 evaluation-session reservation cap. Save version fingerprints, per-rule outcomes, failures, repeat variability and cost estimates even when quality evaluation fails. A semantic mismatch must remain a failed evaluation, not be converted into success; it does not block ordinary code-quality PR checks.
- R7. Restrict live execution to a trusted default-branch revision and existing saved development cases, with the TypeSafe key stored in GitHub Actions secrets. Do not expose that key to PR code or evaluate arbitrary PR refs with credentials. Ordinary PR checks receive no application credentials. Artifacts and logs must exclude secrets and local environment files. Missing credentials should produce a clear setup failure. Held-out model evaluation and version freezing retain the existing deliberate qualification process in `docs/evaluation.md` and are not part of routine CI.

**Bounded rollout**

- R8. Implement this phase as CI for the existing Ruby CLI. Reuse the repository's Ruby version and dependency lockfile, with scoped changes needed for the selected tools. Do not couple delivery of these checks to completion of the GitHub App, passing model-quality qualification, packaging or hosting.

## Success Criteria

- A representative pull request receives explicit results for every required check; a deliberate test, lint/style, dependency-audit or fixture-validation failure is reported as failure.
- Required checks run without TypeSafe or GitHub App credentials, including for fork contributions.
- The initial enforced style baseline is clean without behavior changes or fixture rewrites. Complexity remains visible and non-blocking.
- Coverage and complexity artifacts are accessible, with no coverage minimum imposed. Failed report generation is visible rather than mistaken for zero findings.
- A manual development run records all three repetitions when completed, preserves available results on failure, and cannot use a PR revision with the TypeSafe key. An interrupted run is explicitly incomplete, never qualified.
- Documentation distinguishes code-quality success, live model-quality results and branch-protection configuration. No deployment or model qualification is claimed from CI success.

## Key Decisions and Evidence

- GitHub Actions matches the existing GitHub repository and avoids operating a separate CI service.
- Required lint/style checks plus informational metrics were selected over immediate complexity limits and a coverage minimum.
- The read-only full RuboCop baseline inspected 28 files: 274 offenses, comprising 64 Style, 118 Layout, 91 Metrics and one Bundler offense. The existing lint-only check passes. The most recent recorded RSpec run passed 47 examples.
- `docs/verification/threshold-calibration.md` records only one of four seeded violations detected per fresh pass and variation across repeats. Live Jev quality is therefore a separate experiment, not a required merge gate.
- Deployment, containers, registry publishing, hosting, GitHub App delivery, automatic fixes/merges, paid quality dashboards, new type systems and additional analysis suites are outside this phase. Dependency auditing is a bounded check, not a comprehensive security audit.

## Dependencies and Planning Questions

No user decisions block planning. Verify these technical details during planning:

- [R1, R5] Confirm the default branch, repository visibility, Actions availability and permissions/features needed for required checks; identify any administrator step.
- [R2, R4] Select compatible pinned tool versions, define the non-metric RuboCop rule set, and establish behavior-preserving cleanup and coverage instrumentation details.
- [R4, R5] Define artifact contents/retention and separate metric offenses from tool failures. A new reporting job must not silently suppress execution errors.
- [R6, R7] Verify trusted-ref enforcement, least-privilege workflow permissions, secret handling, concurrent evaluation limits and partial-result upload behavior. The evaluator currently saves individual completed cases; cancelled runs must not appear complete.
- [R2, R6] Account for engine fingerprint changes caused by style cleanup: preserve historical evaluation reports and do not present an old report as qualification for changed code.
- [R1, R8] Choose maintained action revisions and dependency caching while retaining a reproducible install. Refresh external advisory data for dependency auditing and surface update failures.

## Sources

- Repository context: `AGENTS.md`, `Gemfile`, `.rubocop.yml`, `spec/spec_helper.rb`, `docs/evaluation.md`, and `docs/verification/threshold-calibration.md`.
- [GitHub Actions Ruby CI](https://docs.github.com/en/actions/tutorials/build-and-test-code/ruby).
- [bundler-audit capabilities and CI usage](https://github.com/rubysec/bundler-audit).
- [SimpleCov coverage tooling](https://github.com/simplecov-ruby/simplecov).

## Next Step

Proceed to `/ce:plan` using this requirements document. No workflow implementation is part of this brainstorm.
