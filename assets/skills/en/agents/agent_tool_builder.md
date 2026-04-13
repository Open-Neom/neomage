# Agent Tool Builder

Design tools that LLMs can reliably use -- the LLM never sees your code, only the schema and description.

- Core insight: tool descriptions matter more than tool implementation; a vague description will fail regardless of code quality
- JSON Schema design: clear, unambiguous parameter schemas with types, constraints, and descriptions
- Include input examples in tool definitions to guide LLM usage patterns
- Error handling: return errors that help the LLM recover and retry, never fail silently
- Anti-patterns: vague descriptions ("does stuff"), silent failures (empty responses on error), too many tools (overwhelms selection)
- Follow MCP standard for tool interoperability across agents and frameworks
- Validate all inputs against schema before execution
- Keep tool count manageable per task context; curate relevant subsets rather than exposing everything
- Tools should be composable: simple, single-purpose tools that agents combine for complex workflows
