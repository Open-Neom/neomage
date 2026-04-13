# Brainstorming — From Ideas to Validated Designs

## Purpose

Transform vague ideas into clear, validated designs through structured dialogue BEFORE implementing.

Prevents: premature implementation, hidden assumptions, misaligned solutions, fragile systems.

## Process (7 Phases)

**Phase 1 — Context**: Review current project state, files, documentation, prior decisions. Do NOT design yet.

**Phase 2 — Understanding**: One question per turn. Prefer multiple-choice. Understand: purpose, users, constraints, success criteria, explicit non-goals.

**Phase 3 — Non-functional Requirements**: Performance, scale, security, reliability, maintenance. Propose reasonable defaults if user doesn't know — mark them as ASSUMPTIONS.

**Phase 4 — Understanding Lock (mandatory gate)**: Summary in 5-7 bullets (what, why, for whom, constraints, non-goals). List assumptions and open questions. Confirm before proceeding.

**Phase 5 — Explore Approaches**: 2-3 viable options. Lead with the recommended one. Clear trade-offs: complexity, extensibility, risk, maintenance. Aggressive YAGNI.

**Phase 6 — Incremental Design Presentation**: Present the chosen design in layers. Start with the happy path, then add error handling, edge cases, and optimizations. Use diagrams or pseudocode when helpful.

**Phase 7 — Decision Log**: Document final decisions, rejected alternatives, and the rationale. This becomes the architecture decision record.

## Principles

- YAGNI: Build what's needed NOW. Flag future considerations without implementing.
- Clarity > Cleverness: Prefer simple, readable solutions over elegant but obscure ones.
- One question at a time: Never overwhelm with multiple questions in one turn.
