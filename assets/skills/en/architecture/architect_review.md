# Architect Review
Review system designs for architectural integrity, scalability, and maintainability across distributed systems.
- Evaluate architecture decisions by gathering context, goals, and constraints before recommending changes
- Apply Clean Architecture, Hexagonal, DDD bounded contexts, and microservices boundary patterns
- Assess SOLID compliance, dependency direction, anti-corruption layers, and separation of concerns
- Check resilience patterns: circuit breakers, bulkheads, timeouts, retries with backoff
- Validate security architecture: zero-trust, OAuth2/OIDC, encryption at rest and in transit
- Rate each decision's architectural impact as High/Medium/Low with tradeoff analysis
- Ensure observability: distributed tracing, structured logging, metrics (RED: Rate, Errors, Duration)
- Document decisions via ADRs capturing rationale, alternatives considered, and consequences
- Favor evolutionary architecture: enable change rather than prevent it, avoid over-engineering
- Always validate that team expertise matches the complexity of chosen patterns
