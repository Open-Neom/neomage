# Database Design
Database design principles: schema design, indexing, ORM selection, and technology choice based on context.
- Ask about database preferences and deployment environment before defaulting to any technology
- SQLite may suffice for simple apps; do not default to PostgreSQL for everything
- ORM selection matters: Drizzle (lightweight, SQL-like), Prisma (type-safe, migrations), Kysely (query builder)
- Schema design: define relationship types, plan primary keys (UUID vs auto-increment), normalize appropriately
- Indexing strategy: index columns used in WHERE/JOIN/ORDER BY; composite indexes for multi-column queries
- Avoid SELECT * in production; only fetch columns you need for the query
- Watch for N+1 queries: use eager loading, batch queries, or DataLoader patterns to eliminate them
- Consider serverless databases (Neon, Turso, PlanetScale) for auto-scaling and cost efficiency
- Do not store JSON when structured columns would be better; JSON is for truly unstructured data
- Validate schema design with EXPLAIN ANALYZE on expected query patterns before deploying
