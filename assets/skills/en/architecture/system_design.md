# System Design — Scalable Architecture Patterns

## Purpose

Design systems that handle growth in users, data, and complexity without requiring rewrites.

## Design Process

1. **Clarify Requirements**: Functional (what it does) vs Non-functional (how well). Estimate scale: users, requests/sec, data volume.

2. **API Design**: Define the contract first. REST/GraphQL/gRPC. Versioning strategy. Error format.

3. **Data Model**: Entities, relationships, access patterns. SQL vs NoSQL decision based on query patterns, not hype.

4. **High-Level Architecture**: Components, communication patterns, data flow. Draw before building.

5. **Deep Dive**: Pick the hardest component. Design it in detail. Identify bottlenecks.

## Key Patterns

- **CQRS**: Separate read/write models when read patterns differ significantly from write patterns.
- **Event Sourcing**: Store events instead of state. Enables audit trails and temporal queries.
- **Saga Pattern**: Manage distributed transactions through compensating actions.
- **Circuit Breaker**: Prevent cascading failures when external services are down.
- **API Gateway**: Single entry point for microservices. Handles auth, rate limiting, routing.

## Scalability Checklist

- [ ] Stateless services (horizontal scaling)
- [ ] Database indexing strategy
- [ ] Caching layer (Redis/Memcached) with invalidation policy
- [ ] CDN for static assets
- [ ] Message queue for async processing
- [ ] Health checks and graceful degradation
- [ ] Monitoring and alerting thresholds
