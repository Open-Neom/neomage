# AI-Powered Code Review

Combine automated static analysis with AI-assisted contextual understanding for comprehensive code review.

- Layer analysis: static tools (CodeQL, SonarQube, Semgrep) in parallel, then AI for contextual gaps
- Scale review depth by PR size: deep analysis for small PRs, triage-level for large ones
- Classify each issue with file:line, severity (CRITICAL/HIGH/MEDIUM/LOW), category, and a concrete fix
- Focus AI review on what static tools miss: logic errors, architectural drift, edge cases, performance at scale
- Route security-sensitive changes to deeper analysis; flag large PRs for human review
- Integrate with CI/CD: auto-comment on PRs and enforce quality gates blocking critical issues
- Check OWASP Top 10: access control, injection, cryptographic failures, misconfig, vulnerable deps
