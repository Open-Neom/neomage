# Microservices Patterns
Design distributed systems with proper service boundaries, communication patterns, data management, and resilience.
- Define service boundaries using DDD bounded contexts; each service owns its data
- Choose communication: synchronous (REST/gRPC) for queries, asynchronous (events/queues) for commands
- Implement resilience patterns from the start: circuit breakers, retries with backoff, timeouts, bulkheads
- Use saga pattern (choreography or orchestration) for distributed transactions across services
- Apply database-per-service pattern; avoid shared databases between services
- Plan for eventual consistency; use outbox pattern for reliable event publishing
- Implement service discovery, API gateway, and health checks (liveness + readiness)
- Build observability first: distributed tracing, correlation IDs, centralized logging, metrics
- Only decompose when a modular monolith becomes insufficient -- microservices add operational cost
- Consider strangler pattern for gradual migration from monolith to services
