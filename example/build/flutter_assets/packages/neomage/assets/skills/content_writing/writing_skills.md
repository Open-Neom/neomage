# Writing Skills for Agent Skill Files

Create, update, and improve agent skill files with proper structure, discoverability, and compliance.

- Skill tiers: Tier 1 (simple, single file <200 lines), Tier 2 (multi-concept, 200-1000 lines), Tier 3 (platform-scale, 10+ products)
- Description must start with "Use when..." to trigger correctly; never summarize the workflow in the description
- Add `metadata.triggers` with 3+ keywords for discoverability (CSO: "SEO for LLMs")
- Use anti-rationalization patterns for discipline skills so agents cannot ignore rules
- Templates by type: technique (how-to), reference (docs), discipline (rules), pattern (design patterns)
- File naming: `name` field matches directory name exactly, SKILL.md filename is ALL CAPS
- Keep SKILL.md under 500 lines; move detailed content to `references/` subdirectory
- Do not use `@` force-loading in cross-references between skills
- Pre-deploy checklist: name matches dir, description starts with "Use when", 3+ triggers, tested with real scenarios
- Workflow: identify goal, select template, apply CSO, add anti-rationalization, test with RED-GREEN-REFACTOR
