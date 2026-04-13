# Context Restoration

Recover and reconstruct project context across long-running or multi-agent AI workflows with minimal information loss.

- Prioritize context components: project overview, architectural decisions, tech stack, recent work, known issues
- Use semantic similarity and relevance filtering to retrieve the most useful context
- Manage token budgets dynamically -- load highest-priority components first
- Support full, incremental, and diff-based restoration modes
- Preserve decision trails and reasoning history for traceability
- Implement three-way merge strategies when combining context versions
- Validate restored context against the current codebase state
- Cache and index context efficiently for fast retrieval on project resumption
