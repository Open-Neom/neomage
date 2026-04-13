# Agent Framework — Building Agentic Systems

## Purpose

Design and implement AI agents that reason, plan, use tools, and complete complex multi-step tasks autonomously.

## Core Architecture

### ReAct Loop (Reason + Act)
```
Observe → Think → Act → Observe → Think → Act → ... → Answer
```

1. **Observe**: Read the current state (tool results, user message, context)
2. **Think**: Reason about what to do next (chain of thought)
3. **Act**: Execute a tool or produce output
4. **Repeat**: Until the task is complete or a limit is reached

### Plan-and-Execute Pattern
```
Plan Phase:  User Request → Decompose → Step 1, Step 2, ... Step N
Execute Phase: For each step → Select Tool → Execute → Verify → Next
Review Phase: Check all results → Synthesize → Respond
```

## Tool Design Principles

- **Clear descriptions**: The agent selects tools based on descriptions. Vague = wrong tool choice.
- **Structured input/output**: JSON schemas for parameters. Typed results.
- **Error messages**: Return actionable errors, not stack traces.
- **Idempotency**: Tools should be safe to retry.

## Anti-Patterns

- **Unlimited autonomy**: Always set iteration limits and token budgets
- **Tool overload**: 10-15 tools max per context. Too many = confusion.
- **Memory hoarding**: Only persist information that's useful for future turns
- **No verification**: Always check tool results before proceeding
- **Silent failures**: Agents should report what went wrong, not silently skip

## Implementation Checklist

- [ ] Define clear tool schemas with descriptions
- [ ] Set max iterations (10-50 depending on task complexity)
- [ ] Implement graceful degradation when tools fail
- [ ] Add logging for each think-act cycle
- [ ] Include cost/token tracking
- [ ] Test with adversarial inputs
