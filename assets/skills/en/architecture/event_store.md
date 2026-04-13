# Event Store Design
Design and implement append-only event stores with streams, ordering, subscriptions, and concurrency control.
- Core requirements: append-only, ordered (per-stream + global), versioned, subscriptions, idempotent
- Each aggregate has its own stream; events have stream_id, version, global_position, and metadata
- Use optimistic concurrency via expected_version checks to prevent conflicting writes
- Technology choice: EventStoreDB (pure ES), PostgreSQL (existing stack), Kafka (high throughput), DynamoDB (serverless)
- PostgreSQL schema: events table with unique(stream_id, version), global_position serial, JSONB data
- Include snapshots table for long-lived aggregates and subscription_checkpoints for consumer tracking
- Index for stream queries, global position subscription, event type filtering, and time-based queries
- Stream IDs should include aggregate type for categorization (e.g., "Order-{uuid}")
- Always include correlation/causation IDs in event metadata for distributed tracing
- Never store large payloads in events; never skip optimistic concurrency; handle backpressure
