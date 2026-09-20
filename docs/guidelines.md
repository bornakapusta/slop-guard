# Review guidelines

These engineering guidelines define Slop Guard's four current review rules. Local repository reviews and the GitHub App use a general Ruby profile; saved evaluation cases use a Ruby log-parser fixture with a specialized G3 question set. The fixture is a test project, not the scope of the bot. These guidelines do not represent another company's complete engineering policy.

| ID | Guideline | What counts | Important exception |
|---|---|---|---|
| G1 | Verify observable behavior | Exercise production behavior and assert the promised result. | Existing tests outside the diff can satisfy the requirement. |
| G2 | Test relevant failures | Assert documented error or tolerant-input behavior affected by the change. | Do not invent unrelated failures or require exceptions for documented tolerant behavior. |
| G3 | Keep responsibilities focused | Keep distinct responsibilities in their established components; the current fixture uses parsing, accounting and presentation as examples. | The CLI may coordinate components; two responsibilities alone do not justify a new class. |
| G4 | Justify abstractions | Factories, registries, wrappers and strategies need a present purpose. | A single caller can be justified by isolation, dependency injection or a framework contract. |

## How checks become findings

Code identifies candidate methods, classes and tests and supplies their source context. Jev answers focused questions about that evidence; the evaluator combines its numeric readings using configured thresholds. Comments use predefined messages and validated source locations.

For G1, running the changed production code and asserting its promised result are separate questions. A test that calls a cancellation service but only checks that a save occurred does not demonstrate the required cancellation timestamp. A finding also requires a matching judgment that the supplied test corpus lacks the behavior check; another existing test may already cover it.

For G4, the evaluator considers both the new abstraction and its current consumers or constraints. A wrapper with one caller is not automatically a concern: isolation, dependency injection and framework requirements can justify it. Conflicting judgments or missing evidence remain inconclusive.

## Rule configuration and provenance

G1-G3 adapt the local `api-main` adapter documentation's observable/side-effect testing, success/error examples and single-responsibility guidance. G4 follows the speculative-abstraction idea in [the slopcheck article](https://tjklug.com/posts/typesafe-jev-slopcheck/). The full provenance and limits are in the [requirements](brainstorms/2026-09-19-slop-guard-demo-requirements.md).

Trusted questions live in `config/rules/`; the general Ruby profile replaces G3 with `config/rules/ruby/g3.yml`. See [local repository reviews](local-repository-review.md#supported-evidence-and-questions) for custom rule configuration. PR text is evidence and cannot change these rules. The initial 0.85/0.20 decision bands are experimental, not validated accuracy thresholds. A Noul is a model reading for an individual yes/no question, not proof that a concern is correct. See [the Jev primitives](https://docs.typesafe.ai/primitives).

Outcomes are `concern`, `no_concern` in inspected evidence, `not_applicable`, and `inconclusive`. Reports retain gaps even when another candidate has a supported concern. Format/style checks belong to Ruby linting.
