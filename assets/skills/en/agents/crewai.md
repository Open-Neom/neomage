# CrewAI Multi-Agent Framework

Design collaborative AI agent teams with role-based agents, structured tasks, and crew orchestration.

- Define agents with specific role, goal, and backstory; be precise (e.g., "Senior React Developer" not "Developer")
- Tasks need clear descriptions, assigned agents, expected output format, and context dependencies
- Two process types: sequential (tasks in order) and hierarchical (manager agent delegates to workers)
- YAML config is recommended: define agents in agents.yaml, tasks in tasks.yaml, wire up in crew.py
- Always specify expected_output on tasks with format details; this is the "done" criteria
- Use context dependencies to chain task outputs (e.g., writing_task depends on research_task)
- Enable planning feature for complex workflows to generate step-by-step execution plans
- Keep crews to 3-5 agents with clear non-overlapping roles; use tools instead of agents for simple actions
- Anti-patterns: vague agent roles, missing expected outputs, too many agents creating coordination overhead
- Flows handle complex multi-crew workflows; Crews handle single collaborative task sequences
