# API Design Principles
Build intuitive, scalable, and maintainable REST and GraphQL APIs that delight developers.
- Define consumers, use cases, and constraints before designing any API
- REST: use nouns for resources, HTTP methods for actions, proper status codes, consistent naming
- GraphQL: design schema as a contract, enforce nullability intentionally, limit query depth
- Version APIs from day one (URL, header, or content negotiation); plan deprecation strategy
- Standardize response formats: consistent envelope, error shapes, pagination, and filtering
- Implement authentication (JWT, OAuth2, API keys) and rate limiting on every public API
- Document thoroughly with OpenAPI/Swagger specs; include working examples in multiple languages
- Optimize for specific clients: mobile (minimal payloads), third-party (stability), internal (flexibility)
- Avoid verbs in REST endpoints, inconsistent response formats, and exposing internal errors
- Choose API style (REST/GraphQL/tRPC) based on context, not default preference
