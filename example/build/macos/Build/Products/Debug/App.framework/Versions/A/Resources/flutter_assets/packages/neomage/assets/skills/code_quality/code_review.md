# Code Review — Effective Review Practices

## Purpose

Review code changes for correctness, maintainability, and adherence to project standards.

## Review Checklist

### Correctness
- [ ] Does the code do what it claims to do?
- [ ] Are edge cases handled?
- [ ] Are error conditions handled gracefully?
- [ ] Is the logic correct (no off-by-one, null issues)?

### Maintainability
- [ ] Is the code readable without comments?
- [ ] Are names descriptive and consistent?
- [ ] Is the complexity reasonable (no deeply nested logic)?
- [ ] Can someone new to the project understand this?

### Performance
- [ ] No unnecessary allocations in hot paths
- [ ] Database queries are indexed
- [ ] No N+1 query problems
- [ ] Appropriate use of caching

### Security
- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] No SQL injection vectors
- [ ] Auth checks on protected endpoints

### Testing
- [ ] Are there tests for new behavior?
- [ ] Do existing tests still pass?
- [ ] Are edge cases covered in tests?
- [ ] Is test data realistic?

## Feedback Guidelines

### Good Feedback
- Be specific: "Line 42: This null check misses the case where `items` is empty"
- Suggest alternatives: "Consider using `firstOrNull` instead of `first` with a try/catch"
- Explain why: "This allocation inside the loop creates GC pressure in production"

### Feedback Categories
- **Blocking**: Must fix before merge (bugs, security, data loss)
- **Suggestion**: Would improve the code but not required
- **Question**: Clarification needed to understand intent
- **Nit**: Style/formatting (only if not auto-formatted)

## Anti-Patterns in Reviews
- Bike-shedding (debating trivial style choices)
- Rubber-stamping (approving without reading)
- Gatekeeping (blocking for personal preferences)
- Drive-by reviews (commenting without context)
