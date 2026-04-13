# Skill Creator

Automate the full skill creation workflow from brainstorming through validation and installation.

- Five phases: brainstorm and plan, enhance prompt (optional), generate files, validate, install
- Brainstorming captures: what the skill does, trigger phrases, skill type, target platforms, one-sentence description
- File generation: create SKILL.md (1500-2000 words ideal), README.md (300-500 words), plus references/examples/scripts dirs
- SKILL.md requirements: YAML frontmatter, third-person description, imperative writing style, progressive disclosure
- Validation checks: YAML completeness, description format, word count limits, writing style compliance
- Installation options: repository-local only, global via symlinks, or both (recommended for auto-updates)
- Support multiple platforms: GitHub Copilot CLI, Claude Code, Codex; detect available platforms automatically
- Use kebab-case for skill directory names; extract author info from git config
- Common auto-fixes: convert second-person to imperative, reformat descriptions, add missing fields
