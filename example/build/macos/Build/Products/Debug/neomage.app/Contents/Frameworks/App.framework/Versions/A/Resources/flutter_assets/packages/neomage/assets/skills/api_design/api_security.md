# API Security Best Practices
Secure API design: authentication, authorization, input validation, rate limiting, and OWASP API Top 10 protection.
- Authentication: JWT with short expiry (1h), refresh tokens in DB (revocable), strong secrets (256-bit+)
- Authorization: check both authentication AND authorization on every request; RBAC or ABAC
- Input validation: validate all inputs with schema (Zod/Joi), use parameterized queries, sanitize HTML
- Rate limiting: per user/IP, stricter on auth endpoints, Redis-backed for distributed, return limit headers
- HTTPS everywhere; security headers (Helmet.js); CORS configured for specific origins only
- Sanitize error messages: never expose stack traces, database details, or internal structure
- OWASP API Top 10: broken object-level auth, broken authentication, unrestricted resource consumption
- Hash passwords with bcrypt (10+ rounds); never store sensitive data in JWT payload
- Log security events; monitor for suspicious activity; keep dependencies updated
- Never trust user input; never use string concatenation for SQL; never disable CORS completely
