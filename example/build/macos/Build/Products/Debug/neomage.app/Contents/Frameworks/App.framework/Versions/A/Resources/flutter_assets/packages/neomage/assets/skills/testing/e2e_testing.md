# E2E Testing Patterns

Build reliable, fast, and maintainable end-to-end test suites that catch regressions before users do.

- Identify critical user journeys and define success criteria before writing tests
- Use stable selectors (data-testid, roles) over brittle CSS selectors or XPaths
- Build test data strategies with isolated, dedicated test accounts and data
- Implement retries, tracing, and artifact capture for debugging flaky failures
- Run in CI with parallelization for speed; capture screenshots/videos on failure
- Test across multiple browsers and responsive breakpoints for critical flows
- Avoid running destructive tests against production; use dedicated test environments
- Fix flaky tests immediately -- they erode confidence and mask real failures
