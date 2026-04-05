# Saga Orchestration
Manage distributed transactions and long-running workflows with compensating actions.
- Two types: choreography (services react to events) and orchestration (central coordinator directs steps)
- Saga states: Started, Pending, Compensating, Completed, Failed -- track all transitions
- Each step has an action and a compensating action (rollback); compensation must always work
- On step failure, compensate all previously completed steps in reverse order
- Make every step idempotent so retries are safe; use correlation IDs for end-to-end tracing
- Implement timeouts for each step -- do not wait forever for responses
- Orchestration is easier to understand and debug; choreography scales better but is harder to trace
- Log everything: step execution, compensation, failures, and timing for debugging
- Test compensations thoroughly -- they are the most critical part of the saga
- Use async messaging between steps; never couple services synchronously within a saga
