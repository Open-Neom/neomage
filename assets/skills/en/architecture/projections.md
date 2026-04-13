# Projection Patterns
Build read models and materialized views from event streams for optimized query performance.
- Projections transform event streams into query-optimized read models (views, tables, search indexes)
- Design each projection for a specific query pattern -- one projection per read use case
- Projections must be rebuildable from scratch by replaying all events from the store
- Implement idempotent event handlers so replays and retries produce identical results
- Track projection position (checkpoint) to resume after failures without reprocessing
- Use eventual consistency: read models may lag behind the write side by seconds
- Support multiple projection types: SQL tables, search indexes, caches, real-time dashboards
- Aggregate data across multiple event streams for cross-entity queries and reporting
- Monitor projection lag and health; alert when read models fall too far behind
- Test projection rebuilds regularly to ensure they produce correct state from events
