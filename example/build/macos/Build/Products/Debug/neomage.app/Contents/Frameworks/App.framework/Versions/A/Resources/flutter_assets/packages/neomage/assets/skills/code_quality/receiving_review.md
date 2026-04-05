# Receiving Code Review

Handle review feedback with technical rigor: verify before implementing, push back when wrong, no performative agreement.

- Response pattern: READ completely, UNDERSTAND (restate), VERIFY against codebase, EVALUATE technically, RESPOND or IMPLEMENT
- Never say "great point" or "you're right" -- just fix it or push back with reasoning
- If any feedback item is unclear, stop and ask before implementing anything
- For external reviewers: check if technically correct for THIS codebase, verify it won't break things, check if reviewer has full context
- Apply YAGNI check: if a suggested feature is unused, question whether it should be added
- Implementation order: clarify unclear items first, then blocking issues, simple fixes, complex fixes
- Push back when: suggestion breaks functionality, violates YAGNI, is technically wrong, or conflicts with architectural decisions
- When wrong about a pushback, state the correction factually and move on
