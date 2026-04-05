# Workflow Orchestration Patterns

Design durable workflows with Temporal for distributed systems, sagas, state management, and long-running processes.

- Fundamental rule: Workflows = orchestration/decision logic (deterministic); Activities = external interactions (can be non-deterministic)
- Workflows must be deterministic: same inputs produce identical outputs; no threading, random, datetime.now, or direct I/O
- Activities must be idempotent: calling N times equals calling once; use idempotency keys and upserts
- Saga pattern: register compensation before executing each step; on failure, run compensations in reverse (LIFO)
- Entity workflows (actor model): one workflow per entity (cart, account); receives signals, supports queries
- Fan-out/fan-in: spawn child workflows for parallelism; keep each workflow bounded (1K children x 1K tasks)
- Async callback: workflow sends request and waits for signal from external system or human approval
- State preservation is automatic; event history records every command for seamless crash recovery
- Prohibited in workflows: threading, random(), global state, datetime.now(), direct file/network I/O
- Configure retry policies with exponential backoff; classify errors as retryable vs non-retryable
- Use activity heartbeats to detect stalled long-running tasks and enable progress-based retry
