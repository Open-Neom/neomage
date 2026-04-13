# GraphQL Architect
Enterprise-scale GraphQL: federation, performance optimization, real-time subscriptions, and security hardening.
- Apollo Federation v2 for multi-team schemas; schema registry for governance and evolution
- Schema-first development with SDL; Relay specification for connection/pagination patterns
- DataLoader pattern resolves N+1; persisted queries and APQ reduce parsing overhead
- Multi-tier caching: field-level, query-level, CDN with Redis; cache invalidation via dependency tracking
- Security: field-level RBAC, JWT validation, rate limiting via query cost analysis, input sanitization
- Real-time: WebSocket subscriptions with proper filtering, authorization, and cleanup
- Testing: unit test resolvers, integration test with test clients, schema breaking change detection
- Performance monitoring: resolver tracing, query analytics, complexity scoring, field usage tracking
- Migration from REST: gradual via gateway aggregation; maintain backward compatibility
- Design schemas for long-term evolution; deprecate fields with timelines, not removal
