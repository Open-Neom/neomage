# Backend Security

Secure backend coding: input validation, injection prevention, API hardening, and defense-in-depth.

- Validate all inputs with allowlist approaches; reject unexpected types, sizes, and formats at the boundary
- Use parameterized queries exclusively; never concatenate user input into SQL, NoSQL, or LDAP queries
- Sanitize outputs context-aware: HTML-encode for templates, JSON-escape for APIs, URL-encode for redirects
- Set security headers: CSP with nonces, HSTS, X-Frame-Options DENY, X-Content-Type-Options nosniff, strict Referrer-Policy
- CSRF protection: anti-CSRF tokens for state-changing operations, validate Origin/Referer headers, enforce SameSite cookies
- API security: authenticate every endpoint, implement rate limiting, validate content-type, enforce payload size limits
- SSRF prevention: allowlist outbound destinations, block internal IPs, restrict protocols to https
- Error handling: return generic messages to clients, log details server-side without PII, fail closed
- Secrets management: use environment variables or vault services, rotate credentials, never hardcode
- Logging: record auth events and failures, sanitize logs against injection, integrate with SIEM for alerting
- Apply defense-in-depth: multiple security layers, least privilege for all access, regular dependency updates
