# Evaluation Methods for Agent Systems

Build evaluation frameworks that account for non-determinism, multiple valid paths, and composite quality dimensions.

- Key insight: agents may take completely different valid paths to reach goals -- evaluate outcomes, not specific execution steps
- Performance drivers (BrowseComp finding): token usage explains 80% of variance, tool calls ~10%, model choice ~5%; model upgrades beat token increases
- Multi-dimensional rubric: factual accuracy, completeness, citation accuracy, source quality, tool efficiency -- each scored 0.0-1.0 with weighted average
- LLM-as-Judge: provide clear task description, agent output, ground truth, evaluation scale with level descriptions; request structured judgment
- Human evaluation catches what automation misses: hallucinated answers, system failures, subtle biases; sample systematically, track patterns
- End-state evaluation: for agents that mutate state, check final state matches expectations regardless of path taken
- Test set design: span complexity levels (simple single-tool to very complex extended interaction); sample from real usage; include known edge cases
- Context engineering evaluation: test different context strategies on same test set; run degradation tests at different context sizes to find performance cliffs
- Continuous evaluation: automated pipeline on every agent change; production monitoring via random sampling; dashboards for trend analysis
- Avoid: overfitting to specific paths, single-metric obsession, ignoring edge cases, neglecting context effects, skipping human review
