# Security Audit — Vulnerability Assessment

## Purpose

Systematically identify security vulnerabilities in codebases and configurations.

## Audit Checklist

### 1. Secrets & Credentials
- [ ] No hardcoded API keys, passwords, tokens in source code
- [ ] `.env` files are in `.gitignore`
- [ ] Secrets use environment variables or secure storage
- [ ] No credentials in git history (`git log -p | grep -i password`)

### 2. Input Validation
- [ ] All user inputs are validated and sanitized
- [ ] SQL queries use parameterized statements (no string concatenation)
- [ ] File paths are validated against directory traversal (`../`)
- [ ] JSON/XML parsing has size limits

### 3. Authentication & Authorization
- [ ] Passwords are hashed (bcrypt/argon2), never stored in plaintext
- [ ] Session tokens have expiration
- [ ] API endpoints check authorization, not just authentication
- [ ] OAuth flows use state parameter against CSRF

### 4. Data Protection
- [ ] Sensitive data encrypted at rest (database, local storage)
- [ ] HTTPS enforced for all external communication
- [ ] PII has access controls and audit logging
- [ ] Backups are encrypted

### 5. Dependency Security
- [ ] No known vulnerabilities in dependencies (`pub audit`, `npm audit`)
- [ ] Dependencies are pinned to specific versions
- [ ] Transitive dependencies reviewed for trust

### 6. Error Handling
- [ ] Error messages don't leak internal details (stack traces, paths, versions)
- [ ] Failed operations don't leave system in inconsistent state
- [ ] Rate limiting on authentication endpoints

## Severity Levels

| Level | Description | Example | Action |
|-------|------------|---------|--------|
| Critical | Active exploitation possible | Hardcoded admin password | Fix immediately |
| High | Exploitable with effort | SQL injection | Fix within 24h |
| Medium | Requires specific conditions | Missing rate limit | Fix within sprint |
| Low | Minimal impact | Verbose error messages | Track in backlog |

## Reporting Format

For each finding:
1. **Location**: File, line, function
2. **Severity**: Critical/High/Medium/Low
3. **Description**: What's wrong
4. **Impact**: What an attacker could do
5. **Remediation**: How to fix it
6. **Verification**: How to confirm it's fixed
