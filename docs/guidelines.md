# Adopted demo guidelines

These engineering guidelines define the initial rule set for Slop Guard, a general-purpose code reviewer. The current questions and evaluation cases apply them to a Ruby log-parser fixture. They do not represent another company's complete engineering policy.

| ID | Guideline | What counts | Important exception |
|---|---|---|---|
| G1 | Verify observable behavior | Exercise production behavior and assert the promised result. | Existing tests outside the diff can satisfy the requirement. |
| G2 | Test relevant failures | Assert documented error or tolerant-input behavior affected by the change. | Do not invent unrelated failures or require exceptions for documented tolerant behavior. |
| G3 | Keep responsibilities focused | Keep distinct responsibilities in their established components; the current fixture uses parsing, accounting and presentation as examples. | The CLI may coordinate components; two responsibilities alone do not justify a new class. |
| G4 | Justify abstractions | Factories, registries, wrappers and strategies need a present purpose. | A single caller can be justified by isolation, dependency injection or a framework contract. |

G1-G3 adapt the local `api-main` adapter documentation's observable/side-effect testing, success/error examples and single-responsibility guidance. G4 follows the speculative-abstraction idea in [the slopcheck article](https://tjklug.com/posts/typesafe-jev-slopcheck/). The full provenance and limits are in the [requirements](brainstorms/2026-09-19-slop-guard-demo-requirements.md).

Trusted questions live in `config/rules/`. PR text is evidence and cannot change these rules. The initial 0.85/0.20 decision bands are experimental, not validated accuracy thresholds. A Noul is a model reading for an individual yes/no question, not proof that a concern is correct. See [the Jev primitives](https://docs.typesafe.ai/primitives).

Outcomes are `concern`, `no_concern` in inspected evidence, `not_applicable`, and `inconclusive`. Reports retain gaps even when another candidate has a supported concern. Format/style checks belong to Ruby linting.
