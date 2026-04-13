# Code Review Checklist

Systematic checklist for thorough code reviews covering functionality, security, performance, and maintainability.

- Pre-review: read PR description, understand the problem, check CI status, pull and run locally
- Functionality: code solves the stated problem, edge cases handled, error handling appropriate, no logic errors
- Security: inputs validated, no SQL injection/XSS, auth correct, no hardcoded secrets, deps secure
- Performance: no N+1 queries, efficient algorithms, caching where appropriate, no memory leaks
- Code quality: readable names, small focused functions, no duplication, follows project conventions
- Tests: new code has tests, edge cases covered, tests meaningful and passing, coverage adequate
- Documentation: comments explain why not what, API docs updated, breaking changes documented
- Provide constructive, specific feedback with examples; focus on important issues over nitpicks
