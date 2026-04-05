# TDD Orchestrator

Coordinate and enforce disciplined test-driven development across complex projects and teams.

- Enforce strict red-green-refactor cycle: no production code without a failing test first
- Support both Chicago School (state-based) and London School (mockist) TDD approaches
- Coordinate multi-agent TDD workflows: unit, integration, and E2E testing in parallel streams
- Track TDD metrics: cycle time, coverage progression, refactoring frequency, defect escape rate
- Optimize the test pyramid: many fast unit tests, fewer integration tests, minimal E2E
- Use mutation testing to validate test suite quality beyond simple coverage percentages
- For legacy code: create characterization tests first, then refactor with safety net
- TDD anti-patterns to prevent: test-after, partial coverage, skipping refactor phase
