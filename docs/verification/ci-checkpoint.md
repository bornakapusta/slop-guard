# CI checkpoint — 2026-09-20

Implementation: [PR 1](https://github.com/bornakapusta/slop-guard/pull/1), branch `feat/ci-code-quality`. All temporary probes were removed after verification. No merge or new paid evaluation was performed.

## Hosted evidence

| Revision | Run | Observed result |
|---|---|---|
| `d502475c401cba142c92624ad5b0e2439766b762` | [Initial CI](https://github.com/bornakapusta/slop-guard/actions/runs/35496214569) | All 5 jobs passed; fresh Linux dependency installation succeeded |
| `83c346342b29636aa1c459fa3fc5afb2a8d616d3` | [Required-check and environment probes](https://github.com/bornakapusta/slop-guard/actions/runs/35496284129) | Tests failed deliberately; PR merge state BLOCKED; environment job rejected before any step |
| `1a908537bca871b71c7206a347f2fd3e5bc1f2df` | [Optional failure probe](https://github.com/bornakapusta/slop-guard/actions/runs/35496331264) | All 4 required checks passed while optional environment job failed; merge state UNSTABLE/MERGEABLE, no required-check blocker |

The restored workflow matches the initial successful revision. The final documentation commit receives another full CI run; see the PR's latest checks for its exact revision and status. No merge attempt was made during the probes.

Observed check contexts are `Tests`, `Static analysis`, `Dependencies`, `Fixtures`, and `Complexity`, from GitHub Actions integration 15368. Coverage reports 661/849 lines (77.85% as displayed by SimpleCov) and 218/330 branches (66.06%); there are 102 informational Metrics offenses. RSpec reports 58 examples, zero failures.

Downloaded all 5 successful-run artifacts: exactly 7 allowlisted files (RSpec JSON, coverage HTML/JSON, RuboCop JSON, Metrics JSON, audit JSON, fixture JSON). GitHub expiry dates confirm 14-day retention. Inspected source inventory excludes specs, fixtures, dependencies and generated directories; both CLI entry points are included. The failing hosted spec run retained RSpec and coverage artifacts. Neither downloaded artifact set contains the local TypeSafe key or `.env`.

## Enforcement and credential boundary

The active [Main code quality ruleset](https://github.com/bornakapusta/slop-guard/rules/23722882) requires a PR, the first 4 contexts above from integration 15368, and strict up-to-date checks. It has zero mandatory approvals and no bypass actors; the API reports the current administrator cannot bypass it. Complexity and Jev development are excluded. The initial green revision reported CLEAN/MERGEABLE after activation; the deliberate test failure reported BLOCKED.

The `jev-evaluation` environment has exactly one custom deployment policy: `main`, type `branch`, no tags. The existing TypeSafe key is configured there, with no repository-level secret duplicate. A temporary PR job requested this environment without a workflow condition or secret reference. GitHub rejected it with: `Branch "refs/pull/1/merge" is not allowed to deploy to jev-evaluation due to environment protection rules.` The rejected job executed zero steps. This verifies a server-side boundary independently of workflow preflight.

## Local verification

- Ruby 3.4.5, Bundler 2.7.2, RuboCop 1.91.0, bundler-audit 0.9.3, SimpleCov 1.3.0. External action SHAs rechecked; actionlint 1.7.12 accepts both workflows.
- 58 RSpec examples pass, non-Metrics style baseline is clean, offline validation accepts all 24 saved cases. No fixture, label, question or threshold changes.
- Dependency audit has no findings using ruby-advisory-db commit `44784c295391577f25d198a9205eae4ba73ec4da`.
- Actual Metrics workflow command accepts metric offenses and rejects injected Ruby syntax errors and invalid RuboCop configuration. Probes removed.
- An intentionally failing spec returns exit 1 and retains coverage. An unloaded temporary Ruby file and both entry points are included at zero coverage. Probes removed.
- Captured evaluator state and generated questions across all 24 cases, using fixed mock readings, match the pre-cleanup capture. This does not establish live model behavior.
- Summary tests cover incomplete inventory, missing/malformed reports, nonzero evaluator exits, provider failures, contradictory metrics and provisional labels. Rendering the preserved historical calibration report produces FAILED with its 48 completed pairs and historical costs intact.
- Executed the actual preflight shell with main, feature and tag refs: exit 0, 2 and 2 respectively. An empty key exits 2 before evaluator launch. No provider calls were made.

## Remaining verification after merge

- Dispatch **Development evaluation** once from `main` after the workflow reaches the default branch. Verify the fresh main run's summaries and retained report/ledger. This is a paid development run with a new $2 reservation budget, not model qualification.
- Exercise a non-main manual dispatch and tag denial on GitHub, plus controlled step timeout/partial artifact retention. PR environment denial and local preflight are already verified; they do not prove these separate runtime paths.
- First-time fork contribution approval/secret isolation and cancellation of obsolete CI runs remain not live-verified. Runner loss or cancellation can prevent uploads.
- An actual failed paid evaluation was not dispatched. The optional failure probe and required-check configuration establish that an optional check is excluded, not that Jev has run successfully on GitHub.

Green code-quality CI remains separate from the historical failed model-quality baseline. Source/lockfile fingerprints changed; no new qualification claim is made.
