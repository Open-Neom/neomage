# Autonomous Agents

Design AI agents that independently decompose goals, plan, execute tools, and self-correct reliably.

- Core insight: a 95% success rate per step drops to 60% by step 10 due to compounding error -- minimize step count
- Autonomy is earned, not granted: start with heavily constrained agents that do one thing reliably, then expand
- ReAct loop: alternate reasoning (Thought) and action (Action/Observation) steps with max iteration limits
- Plan-Execute pattern: separate planning phase from execution; replan based on intermediate results
- Reflection pattern: self-evaluate after actions, iteratively improve before final output
- Anti-patterns: unbounded autonomy (no limits), trusting agent outputs without validation, general-purpose autonomy (too broad)
- Always set hard cost limits, validate outputs against ground truth, apply least privilege for tool access
- Track context usage to avoid overflow; implement structured logging for debugging agent behavior
- Test at scale before production; build robust API clients with retries and error handling
- Guardrails before capabilities, logging before features -- the best agents are less impressive but work consistently
