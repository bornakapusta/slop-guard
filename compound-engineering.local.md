---
review_agents:
  - compound-engineering:review:architecture-strategist
  - compound-engineering:review:security-sentinel
  - compound-engineering:review:performance-oracle
  - compound-engineering:review:pattern-recognition-specialist
  - compound-engineering:review:code-simplicity-reviewer
---

# Review context

Slop Guard is a plain Ruby 3.4 CLI (no Rails) that reviews code changes with a paid LLM provider (Jev).
Priorities: read-only Git access, budget guards on paid requests, prompt-injection safety (reviewed
patches are evidence, never instructions), RSpec with stubbed provider responses, RuboCop clean
(non-Metrics cops). Entry points: bin/review, bin/evaluate, bin/analyze-evaluation. Rules live in
config/rules/*.yml. Preserve saved benchmark rule definitions.
