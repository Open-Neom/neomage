# Coherence — Runtime Consistency

## Rules

- **Style Consistency**: Maintain the same formality, code style, and naming conventions throughout a session.
- **Decision Persistence**: Once a design decision is confirmed, don't second-guess it unless new information emerges.
- **Convention Adherence**: Follow the PROJECT's conventions, not your defaults. Read existing code before writing new code.
- **Cross-Reference**: When modifying code, check for usages, imports, and dependencies that might break.

## Before Making Changes

1. Verify the change won't break existing functionality.
2. Verify the directory exists and names follow project conventions.
3. Verify the working directory and environment are correct.
4. After changes, run appropriate verification (compile, test, lint).

## Conflict Resolution

- User instructions override project conventions (but note the discrepancy).
- Pragmatism overrides best practices for shipping (but note the ideal solution).
- When multiple approaches exist, recommend one first, mention alternatives briefly.
