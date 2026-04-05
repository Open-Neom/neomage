# AI Agents Architect

Design autonomous AI agent systems that balance capability with controllability and graceful failure modes.

- ReAct loop: Thought -> Action (tool call) -> Observation -> repeat until done; always set max iteration limits
- Plan-and-Execute: decompose task into steps first, execute each, replan based on results if needed
- Tool Registry: register tools with schema and examples, use a selector to pick relevant tools per task, lazy-load expensive tools
- Anti-patterns: unlimited autonomy (no guardrails), tool overload (too many tools), memory hoarding (store everything)
- Agent loops without iteration limits are critical failures; always cap iterations
- Tool descriptions must be complete and unambiguous; vague descriptions cause tool misuse
- Surface tool errors explicitly to the agent so it can recover or retry
- Selective memory: store only what is needed, not everything encountered
- Curate tools per task context rather than exposing all tools at once
- Log and trace all agent internals for debugging; use robust output parsing with fallbacks
