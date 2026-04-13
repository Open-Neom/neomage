# Subagent-Driven Development

Execute implementation plans by dispatching a fresh subagent per task with two-stage review after each.

- Core principle: fresh subagent per task + two-stage review (spec compliance then code quality) = high quality, fast iteration
- Controller reads plan once, extracts all tasks with full text, creates TodoWrite, then dispatches sequentially
- Each task: dispatch implementer subagent -> answer any questions -> implementer implements/tests/commits/self-reviews
- Review stage 1: spec compliance reviewer checks code matches spec exactly (no missing, no extra)
- Review stage 2: code quality reviewer checks implementation quality (only after spec review passes)
- If reviewer finds issues: same implementer fixes, reviewer re-reviews; repeat until approved
- Never: skip reviews, dispatch parallel implementers (conflicts), make subagent read plan file (provide full text), start quality review before spec compliance passes
- Fresh context per task prevents confusion and context pollution between tasks
- After all tasks: dispatch final code reviewer for entire implementation, then finish development branch
- Subagents follow TDD naturally; questions are surfaced before work begins, not after
