# Database Migration
Execute schema and data migrations across ORMs with zero-downtime strategies and rollback procedures.
- Every migration needs both up() and down() -- always provide rollback capability
- Zero-downtime pattern (expand-contract): add new column -> deploy dual-write code -> backfill -> switch reads -> drop old column
- Use transactions for atomic migrations; create backup tables for destructive operations
- Break large migrations into small, incremental steps; avoid migrating too much data at once
- ORM support: Sequelize (queryInterface), TypeORM (MigrationInterface), Prisma (prisma migrate)
- Column renames require multi-step: add new -> copy data -> update app -> remove old
- Type changes require multi-step: add new typed column -> transform data -> drop old -> rename
- Handle NULL values explicitly; consider foreign key constraints during schema changes
- Test migrations on staging first; verify data integrity before and after with validation queries
- Migrations should be idempotent: safe to re-run without causing errors or data corruption
