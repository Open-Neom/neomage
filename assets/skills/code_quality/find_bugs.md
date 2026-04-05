# Find Bugs

Systematically review branch changes for bugs, security vulnerabilities, and code quality issues.

- Get the full diff against the default branch; read every changed line completely
- Map the attack surface: user inputs, DB queries, auth checks, external calls, crypto operations
- Run the security checklist on every file: injection, XSS, auth, IDOR, CSRF, race conditions, crypto, info disclosure, DoS, business logic
- Verify each finding: check if handled elsewhere, search for existing tests, read surrounding context
- Before concluding, audit your own work: confirm every file was fully read, every checklist item checked
- Prioritize: security vulnerabilities > bugs > code quality; skip stylistic issues
- Report with file:line, severity, problem, evidence, concrete fix, and references (OWASP, CWE)
- If nothing significant is found, say so honestly; never invent issues
