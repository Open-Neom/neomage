# SAST Security Scanning

Static Application Security Testing across Python, JS/TS, Java, Ruby, Go, Rust, and PHP.

- SAST analyzes source code without execution to find injection, secrets, misconfig, and unsafe patterns
- Tool selection by language: Bandit (Python), ESLint-security (JS/TS), Semgrep (multi-lang), SpotBugs (Java), Brakeman (Ruby), gosec (Go)
- Semgrep is the universal choice: supports custom rules, OWASP Top 10 rulesets, and CI-native operation
- Key vulnerability patterns: SQL injection (string formatting in queries), XSS (innerHTML with user input), hardcoded secrets, path traversal, command injection, insecure deserialization
- Secure alternatives: parameterized queries, textContent/DOMPurify, environment variables, path validation, subprocess with array args, json.loads/yaml.safe_load
- Framework-specific: Django (no csrf_exempt, DEBUG=False, security middleware), Flask (Talisman, strict CORS), Express (helmet, rate limiting)
- CI integration: run on every PR, block on critical/high findings, upload reports as artifacts, use Semgrep CI mode
- Custom rules: write organization-specific Semgrep rules for internal security policies and coding standards
- Triage: combine multiple tools for coverage, tune false positives with exclusions, prioritize by severity and confidence
- Best practices: run early (pre-commit hooks), combine with DAST, update tools regularly, track baseline of known issues
