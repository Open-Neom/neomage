# CQRS Implementation
Separate read and write models for independent scaling, optimized queries, and event-sourced systems.
- Commands mutate state through a write model; queries read from optimized read models (projections)
- Read and write models can use different databases, schemas, and optimization strategies
- Projections are rebuilt from events -- design them for specific query patterns
- Accept eventual consistency between write and read sides; plan for propagation delay
- Synchronize read models via events, change data capture, or direct projection updates
- Only apply CQRS when read/write workloads differ significantly; simple CRUD does not need it
- Define clear command boundaries: one command handler per aggregate or business operation
- Validate commands before execution; queries should never have side effects
- Plan for projection rebuilding: idempotent handlers, replay capability, and versioning
- Combine with event sourcing for full audit trails and temporal queries
