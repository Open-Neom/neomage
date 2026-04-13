# API Patterns
API design principles and decision-making: REST vs GraphQL vs tRPC, response formats, versioning, pagination.
- Choose API style based on context: REST for public/partner APIs, GraphQL for complex UIs, tRPC for TS monorepos
- REST: resource naming with nouns, proper HTTP methods and status codes, HATEOAS for discoverability
- GraphQL: schema-first design, enforce query depth/complexity limits, disable introspection in production
- Standardize response envelope: consistent shape for success, errors, pagination across all endpoints
- Versioning strategies: URI (/v1/), header (Accept-Version), query param -- pick one and be consistent
- Authentication: JWT for stateless, OAuth2 for third-party, API keys for service-to-service, Passkeys for modern UX
- Rate limiting: token bucket or sliding window; return X-RateLimit headers; protect auth endpoints more strictly
- Document with OpenAPI/Swagger; keep docs generated from code to prevent drift
- Never default to REST for everything; never use verbs in REST endpoints; never skip rate limiting
- Always ask about API consumers and their requirements before making design decisions
