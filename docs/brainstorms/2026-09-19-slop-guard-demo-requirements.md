---
date: 2026-09-19
topic: slop-guard-demo
---

# Slop Guard: Guideline-Based Review Demo

## Problem Frame

Developers need review feedback tied to explicit engineering guidelines, with enough evidence to understand and correct a concern. Generic suggestions or confident findings without the relevant context undermine trust.

The first milestone is a repeatable GitHub demonstration using the existing Ruby log-parser project. The audience should understand the feature, see a guideline violation identified on a PR, and see the review update after the fix. This is an evaluation of a small reviewer, not a claim that it can establish complete correctness or compliance.

Slop Guard lives in its own repository. A Ruby GitHub App receives PR events, gathers review evidence, asks Jev focused questions, and publishes advisory feedback. This follows the slopcheck article's division of responsibility: code enumerates evidence and controls decisions; Jev supplies bounded judgments. Project-guideline traceability and feature-to-test coverage are our extensions.

## Agreed Demo Guidelines

The user selected all four guidelines below. They are explicit adaptations for log-parser, not a claim to reproduce another organization's complete standards.

| ID | Guideline | Application and boundary | Source basis |
|---|---|---|---|
| G1 | Tests verify observable feature behavior. | Tests exercise the relevant production behavior and assert promised results. A test confirming only a configured mock value is insufficient. Existing tests may satisfy a new PR's requirements. | Adapted from `api-main`'s `docs/adapter-pattern.md`, Testing Patterns and Testing Side Effects; feature coverage is an extension requested in this brainstorm. |
| G2 | Changed behavior includes relevant failure cases. | When a feature changes input validation or error behavior, tests cover the relevant documented failure cases. Unrelated hypothetical failures do not justify a finding. | Adapted from success and error-response examples in `api-main`'s `docs/adapter-pattern.md`, Testing HTTP Adapters with WebMock. |
| G3 | Keep responsibilities focused. | Changes preserve clear purposes for parsing, counting, and presentation. Identify the specific responsibility being mixed and its consequence; do not demand a new class merely to satisfy a preference. | Adapted from the single-responsibility principle in `api-main`'s `docs/adapter-pattern.md`, Architecture Overview. |
| G4 | Avoid speculative abstractions. | Added factories, interfaces, strategies, or wrappers need a demonstrated purpose. A single caller alone is not proof of a violation: consider existing callers, testability, framework requirements, and explicit project constraints. | The slopcheck article's speculative-abstraction check, with explicit context and exception handling. |

Ruby formatting and mechanically enforceable lint rules remain the responsibility of existing lint tools. They are not additional Jev review rules.

## Requirements

**Review scope and evidence**

- R1. Review opened, reopened, and updated PRs in the installed log-parser demo repository. Re-evaluate when commits or the PR's described expected behavior change. Review one identified head commit against its identified base; attach the result to that head commit.
- R2. Review the effects of the PR against G1-G4. Gather the diff, relevant complete Ruby source and tests, the project guidelines, and PR purpose/expected behavior. Do not turn a PR review into an unsolicited audit of unchanged code.
- R3. Demo PR descriptions include a short Before/After description and explicit expected behavior. Use those expectations and established project behavior to evaluate tests. Do not invent acceptance criteria from the implementation alone. Missing or contradictory expectations make affected checks inconclusive; independent checks can still run.
- R4. Count existing relevant tests as evidence. Distinguish missing tests from tests outside the inspected context. When context is missing, unsupported, truncated, or otherwise inadequate, report the affected checks as inconclusive rather than claiming a violation or a pass.
- R5. Translate the four guidelines into reviewed, versioned question templates and explicit exceptions before reviewing PRs. Ask atomic questions and combine their answers in Ruby. Jev does not generate guidelines, review prose, executable actions, or new rules during a PR review. Arbitrary guideline-document ingestion is outside this milestone.

**Findings and GitHub behavior**

- R6. Publish inline findings where a relevant changed line can accurately anchor the concern, plus one maintained PR summary. Each finding identifies the guideline, concrete evidence, affected expected behavior where applicable, and a predefined explanation and correction hint. Include the relevant model reading and applied threshold, labeled as review signals rather than certainty. If a missing test has no suitable changed-line anchor, put the finding in the summary with source references; do not invent a location.
- R7. Present findings as advisory concerns. Never submit an approval, request-changes review, or make code changes. The review check is not configured as a merge requirement. A completed run with findings remains distinguishable from an incomplete or failed run without enforcing a merge decision.
- R8. The summary identifies the reviewed commit, guidelines considered, findings, inconclusive checks, and skipped material. Supported per-guideline outcomes are concern found, no concern found in inspected evidence, not applicable, and inconclusive. No-findings language must not claim the PR is correct or fully tested.
- R9. On re-review, update the summary and identify prior findings as still present, no longer observed after successful re-evaluation, or not re-evaluated. Do not call a finding fixed when context was lost or a request failed. Duplicate events must not duplicate comments, and results for older review inputs must not replace the current review. This includes changes to PR expectations on the same head commit, as well as new commits or updated rules. Retain human discussion; detailed GitHub thread mechanics belong in planning.
- R10. Missing credentials, unavailable models, rate limits that cannot be recovered within the review budget, invalid answers, context limits, and GitHub publication errors must result in a visible incomplete/failed status where publication is possible. Empty diffs or changes genuinely unrelated to all four guidelines are reported as no applicable changes. Unsupported evidence needed for a guideline makes that check inconclusive, not inapplicable or passed. Preserve completed findings when only part of a review fails.

**Demo validation and operating boundary**

- R11. Keep a labeled set of saved patches and expected findings, including a violation, a legitimate lookalike, and a corrected version for each guideline. Establish labels before model tuning. Include feature tests outside the diff and justified abstractions to exercise false-positive risks.
- R12. Tune questions and thresholds on development examples, then evaluate on separate held-out examples. Freeze the evaluated model, questions, and thresholds for the live demo. Record false positives, missed findings, inconclusive results, API cost, and elapsed time. Model probabilities and combined scores are decision signals, not proof of correctness; do not blindly copy the article's threshold.
- R13. Exercise the real integration on GitHub: open a labeled PR, observe an inline finding and summary, push its corrected version, and observe the updated review. Recorded or mocked responses can test delivery logic but do not establish live Jev quality or live GitHub behavior.
- R14. Limit the pilot to the selected demo repository and intentionally supplied demo source. Validate webhook authenticity and installation/repository authorization. Treat PR text and code as untrusted evidence, never execute it in the privileged reviewer, and never let it change trusted review rules or authorize actions. Keep credentials out of source, prompts, artifacts, and logs; send Jev only necessary review context. Detailed protections and publication permissions belong in planning.

## Success Criteria

- For each guideline, the agreed violating example produces the expected concern, the legitimate lookalike avoids that concern, and the corrected example no longer produces it. Findings reference the correct guideline and evidence.
- Separate held-out positive and negative examples for each guideline meet their predetermined expected outcomes before calling that guideline demo-ready. Repeat evaluation three times to expose verdict instability. Failures remain recorded and require revising the rule or narrowing its claim, not relabeling the example to fit the model.
- A real log-parser PR demonstrates opening, reviewing, fixing, and re-reviewing, with at least one accurate inline finding and an updated summary. An all-clear result is scoped to the inspected evidence.
- Duplicate delivery, a newer commit arriving during review, missing test context, and a model failure demonstrate the defined behavior without duplicate current findings, stale replacement, or false clearance.
- Tests and lint establish the demo application's baseline independently. The bot never claims that inspecting test code proves test execution passed.

## Scope Boundaries

- One Ruby demo project, four guidelines, advisory feedback, and the GitHub App workflow.
- No general-purpose review agent, automatic fixes, automatic approvals, merge blocking, comprehensive security audit, dashboard, conversational bot, or multi-language support.
- No guarantee of exhaustive feature coverage. G1 and G2 assess identifiable expected scenarios using the inspected evidence.
- No automatic conversion of arbitrary prose guidelines into trusted rules. The four demo rules are maintained deliberately.
- No production deployment claims or broad multi-repository onboarding in this milestone. The bot remains separate from the application so it can be extended later.
- No copying Rails, database, multi-platform, or adapter-factory requirements from `api-main` into the standalone parser.

## Key Decisions

- GitHub App rather than only a CI script: the user selected a separately installed bot with PR-triggered reviews. CI tests and deploys Slop Guard; webhooks trigger reviews. A local review path supports evaluation of saved patches.
- Advisory feedback: usefulness and false positives must be measured before considering enforcement.
- Inline findings plus a summary: show concerns beside code while preserving an overview and space for missing-evidence findings.
- Guidelines drive questions: adapt explicit standards once, rather than asking Jev to invent project preferences on each run.
- Observable behavior matters: checking only mock usage is too narrow for the user's intended value.

## Dependencies and Source Evidence

- At inspection, the local `slop-guard` directory was empty and was not a Git checkout. The local `log-parser-master` directory also lacked Git metadata. GitHub repository identities and App installation are not verified.
- Log-parser already contains a CLI, parsing/counting/presentation classes, RSpec examples, and a Gemfile pinned to Ruby 2.6.5. Its tests and runtime were inspected as source but were not run in this brainstorm. Establishing a working baseline is a prerequisite for demonstration.
- A usable Jev account/API key, GitHub App credentials, and a reachable webhook host are required; availability is unverified. Ruby can use the documented HTTP API; no Ruby SDK is assumed.
- `api-main`'s `README.md` links its primary standards to `smartpension/engineering_docs`, which was not retrieved. Only local `docs/adapter-pattern.md`, `.github/PULL_REQUEST_TEMPLATE.md`, and `.rubocop.yml` were inspected as relevant source material. The Before/After template inspires the demo PR description, with expected behavior added for this demo.
- Source provenance is a drafting reference, not a runtime dependency on the local `api-main` checkout. Publish the adopted log-parser guidelines with the demo so findings can point to a stable, accessible rule.
- [Slopcheck article](https://tjklug.com/posts/typesafe-jev-slopcheck/): diff candidates, predefined questions, threshold composition, evidence locations, and coverage gaps. It does not provide a verified GitHub App implementation or complete feature-coverage evaluator.
- [TypeSafe primitives](https://docs.typesafe.ai/primitives), [confidence](https://docs.typesafe.ai/confidence), and [known limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13): independent questions, calibrated probability intent, literal wording, numeric limitations, and susceptibility to adversarial input. Typed output does not ensure correct judgments.
- [GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps): installation permissions, webhooks, and authenticated publication.

## Outstanding Questions

### Resolve Before Planning

None. Product scope is defined; the following are implementation and feasibility work.

### Deferred to Planning

- [Affects R1, R9, R14][Technical] Choose hosting, webhook processing, minimal run tracking, authentication, and idempotent publication mechanics; verify target repository identities and credentials without exposing secrets.
- [Affects R2, R4, R6][Needs research] Define a bounded Ruby context-selection approach, candidate extraction, existing-test discovery, and GitHub line mapping. Investigate whether this evidence supports the four rules; unsupported cases must remain explicit.
- [Affects R5, R11, R12][Needs research] Write concrete question criteria and representative patches for each guideline. Measure whether design judgment and feature-coverage questions work reliably before expanding the live bot.
- [Affects R10, R12][Technical] Pin the model version and choose measured thresholds, context/cost limits, retry budgets, and review timeouts. Verify current Jev limits and answer shapes.
- [Affects R11, R13][Technical] Establish the log-parser runtime and test baseline, isolate controlled demo changes, and identify required compatibility work. Preserve unrelated application behavior.

## Next Steps

-> `/ce:plan` for structured implementation planning, beginning with rule feasibility and the demo baseline.
