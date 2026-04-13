# Workflow Automation

Build reliable workflow automation using durable execution platforms like n8n, Temporal, and Inngest.

- Without durable execution, network hiccups during multi-step flows mean lost work and broken state
- Platform tradeoffs: n8n is accessible but slower; Temporal is correct but complex; Inngest balances DX with reliability
- Core patterns: sequential (steps in order), parallel (independent steps simultaneously), orchestrator-worker (coordinator dispatches)
- Always use idempotency keys for external calls to handle safe retries
- Break long workflows into checkpointed steps to enable resume from last success
- Always set timeouts on activities; never let them run indefinitely
- Use exponential backoff for retries; avoid fixed intervals
- Keep workflow code deterministic (no side effects); push non-deterministic work into activities
- Pass references (IDs, URLs) between steps, not large data payloads
- Every production workflow needs error handling, monitoring, and alerting
