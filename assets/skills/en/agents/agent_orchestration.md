# Agent Orchestration (Improve Agent)

Systematic improvement of existing agents through performance analysis, prompt engineering, and continuous iteration.

- Phase 1: Establish baseline metrics -- task completion rate, accuracy, tool efficiency, token consumption, user satisfaction, hallucination rate
- Analyze user feedback patterns: corrections, clarification requests, task abandonment, follow-up questions
- Classify failure modes: instruction misunderstanding, output format errors, context loss, tool misuse, constraint violations, edge cases
- Phase 2: Improve prompts via chain-of-thought enhancement, few-shot example optimization, role definition refinement, constitutional AI self-correction loops
- Curate examples from successes; include both positive and negative examples with explanations
- Phase 3: Test with golden path scenarios, regression tests on past failures, edge cases, stress tests, and adversarial inputs
- A/B test original vs improved agent; require 100+ tasks, 95% confidence, and calculate Cohen's d effect size
- Phase 4: Version agents as agent-name-vMAJOR.MINOR.PATCH; staged rollout (5% -> 20% -> 50% -> 100%)
- Rollback triggers: success rate drops >10%, critical errors increase >5%, cost increases >20%
- Success criteria: task success +15%, user corrections -25%, no safety regressions, latency within 10%
