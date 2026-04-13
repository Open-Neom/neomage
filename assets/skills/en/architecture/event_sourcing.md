# Event Sourcing Architect
Store state as a sequence of immutable events for complete audit trails, temporal queries, and complex workflows.
- Events are immutable facts -- never delete or modify committed events in production
- Identify aggregate boundaries and event streams; keep events small and focused
- Design events with versioning from day one; plan for schema evolution and backward compatibility
- Build projections (read models) for each query requirement; plan for projection rebuilding
- Implement snapshotting for long-lived aggregates to avoid replaying entire event history
- Use saga/process managers for cross-aggregate workflows with compensating actions
- Design for eventual consistency; use correlation IDs for end-to-end tracing
- Implement idempotent event handlers to safely handle replays and retries
- Rebuild projections in staging before running in production to catch errors early
- Best for: audit trails, undo/redo, time-travel debugging, complex domain workflows
