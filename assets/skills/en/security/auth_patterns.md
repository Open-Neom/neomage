# Authentication & Authorization Patterns

Secure, scalable auth systems using JWT, OAuth2, sessions, and RBAC.

- Choose auth strategy based on context: sessions for web apps, JWT for APIs, OIDC for SSO/federated identity
- JWT lifecycle: short-lived access tokens (15min), long-lived refresh tokens with rotation, store refresh tokens server-side
- OAuth2 flows: use Authorization Code + PKCE for public clients, Client Credentials for service-to-service
- RBAC/ABAC: enforce authorization at policy enforcement points, never trust client-side role checks alone
- Session management: regenerate session ID on login, set secure/httpOnly/sameSite flags, enforce idle and absolute timeouts
- Password storage: use bcrypt or Argon2id with per-user salts, enforce minimum complexity, support MFA
- Token validation: always verify signature, issuer, audience, and expiration; reject none algorithm
- Secrets: never log tokens or credentials, rotate keys on schedule, use vault services for storage
- Design for least privilege: scope tokens narrowly, prefer deny-by-default policies
- Always plan for token revocation, audit logging, and brute-force protections (rate limiting, lockouts)
