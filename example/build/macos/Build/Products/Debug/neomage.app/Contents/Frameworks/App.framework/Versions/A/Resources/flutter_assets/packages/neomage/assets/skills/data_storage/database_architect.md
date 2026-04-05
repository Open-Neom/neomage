# Database Architect
Design data layers from scratch: technology selection, schema modeling, indexing, and scalable architectures.
- Start with access patterns and scale targets before choosing technology; not everything needs PostgreSQL
- Technology selection: relational (PostgreSQL, MySQL), document (MongoDB, Firestore), time-series (TimescaleDB), graph (Neo4j)
- Schema design: conceptual -> logical (normalize to 3NF) -> physical (denormalize for read patterns)
- Indexing strategy: B-tree default, GIN for JSONB/arrays, partial indexes for filtered queries, composite index column order matters
- Normalization vs denormalization: normalize for write consistency, denormalize for read performance; hybrid with materialized views
- Scaling: read replicas for read-heavy, partitioning (range/hash/list) for large tables, sharding for horizontal scale
- Migration planning: zero-downtime via expand-contract pattern; version-controlled with rollback procedures
- Caching: cache-aside with Redis, materialized views at DB level, CDN for API responses
- Multi-tenancy: shared schema (simplest), schema-per-tenant (isolation), database-per-tenant (strongest isolation)
- Design the data layer right from the start; costly rework comes from wrong technology or model choices
