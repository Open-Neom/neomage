---
name: simplification-help
description: >
  Quick-reference card for all senior dev modes, skills, and commands.
  One-shot display. Trigger with "help senior", "simplification help", or /simplification-help.
license: MIT
---

# Senior Mode Help

Display this reference card when invoked. One-shot, do NOT change mode, write flag files, or persist anything.

## Levels

| Level | Trigger | What change |
|-------|---------|-------------|
| **Lite** | `/senior lite` | Build what's asked, name the simpler alternative in one line. |
| **Full** | `/senior` | The ladder enforced: YAGNI → stdlib → native → one line → minimum. Default. |
| **Ultra** | `/senior ultra` | YAGNI extremist. Deletion before addition. Challenges requirements before building. |

Level sticks until changed or session end.

## Skills

| Skill | Trigger | What it does |
|-------|---------|--------------|
| **senior-developer** | `/senior` | Practical mode itself. Simplest solution that works. |
| **simplification-review** | `/simplification-review` | Over-engineering review: `L42: yagni: factory, one product. Inline.` |
| **technical-debt** | `/technical-debt` | List comments `senior:` in the codebase. |
| **complexity-audit** | `/complexity-audit` | Whole-repo audit for over-engineering. |
| **simplification-help** | `/simplification-help` | This card. |

## Deactivate

Say "stop senior mode" or "normal mode". Resume anytime with `/senior`. `/senior off` also works.
