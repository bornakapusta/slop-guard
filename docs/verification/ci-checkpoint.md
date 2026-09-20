# CI checkpoint — 2026-09-20

Implementation branch: `feat/ci-code-quality`. Remote verification is in progress; this checkpoint will be updated with actual run URLs before handoff.

## Verified locally

- Official action SHAs rechecked; actionlint 1.7.12 accepts both workflows.
- Ruby 3.4.5, Bundler 2.7.2, RuboCop 1.91.0, bundler-audit 0.9.3, SimpleCov 1.3.0.
- RSpec: 58 examples, zero failures. Coverage: 661/849 lines (77.85%), 218/330 branches (66.06%); informational only.
- The new summary correctly renders the preserved 48-case/repeat calibration run as FAILED, with historical costs and metrics intact. No paid call was needed.
- Required non-Metrics style baseline is clean. Offline validation accepts all 24 saved cases.
- Dependency audit has no findings using ruby-advisory-db commit `44784c295391577f25d198a9205eae4ba73ec4da`.
- Actual Metrics workflow command accepts metric offenses and rejects injected Ruby syntax errors and invalid RuboCop configuration. Probes were removed.
- An intentionally failing spec returns exit 1 and retains coverage. An unloaded temporary Ruby file and both entry points are included at zero coverage. Probe files were removed.
- Captured evaluator state and question requests across all 24 cases, with fixed mock readings, match the pre-cleanup capture. Trusted rules and fixture inputs are unchanged. This is contract evidence, not a live model evaluation.

## GitHub settings

- `jev-evaluation` created with custom deployment policy: exactly `main`, type `branch`, no tags.
- Existing TypeSafe key configured as an environment secret without printing its value. No repository-level secrets are configured.
- Main required-check ruleset and hosted CI verification: pending.

## Not yet live-verified

- First-time fork contribution approval/secret isolation and cancellation of obsolete CI runs.
- Main-only manual dispatch, denied branch/tag dispatch, controlled hosted timeout and paid-job artifact retention. The workflow must exist on the default branch before dispatch; no merge or paid run has been performed as part of this checkpoint.
- Green code-quality CI is independent of the historical failed model-quality baseline. No new review-quality claim is made.
