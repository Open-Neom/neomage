# SQL Migrations
Zero-downtime SQL migration strategies for PostgreSQL, MySQL, and SQL Server with validation and rollback.
- Tools: Flyway, Liquibase, Alembic for version-controlled, repeatable migration management
- Zero-downtime strategies: expand-contract (add then remove) or blue-green database deployments
- Pre-migration: analyze impact, estimate duration, verify backups, test on staging
- Migration scripts: version-controlled SQL with framework integration; always include rollback scripts
- Validation suite: pre-migration checks (schema state, data integrity) and post-migration verification
- For large tables: batch processing, parallel execution, chunked operations to minimize lock time
- Monitor migration progress: rows processed, estimated completion, error count, lock contention
- Rollback procedures: automated rollback scripts tested before migration; manual fallback documented
- Handle concurrent operations: minimize exclusive locks, use online DDL where available
- Production-ready checklist: backups verified, rollback tested, monitoring active, team notified
