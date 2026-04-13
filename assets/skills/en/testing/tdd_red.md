# TDD Red Phase

Generate comprehensive failing tests that define expected behavior before any implementation exists.

- Write tests that MUST fail initially; failures should be from missing behavior, not syntax/import errors
- Follow Arrange-Act-Assert pattern with should_X_when_Y naming convention
- Cover: happy paths, edge cases (null, empty, boundary), error handling, concurrent access if applicable
- Framework-specific: Jest/Vitest (vi.fn, testing-library), pytest (fixtures, parametrize), Go (table-driven), RSpec (let, contexts)
- Quality: one behavior per test, meaningful test data, no implementation leakage, tests as living documentation
- Anti-patterns: tests passing immediately, testing implementation vs behavior, complex setup, brittle tests
- Edge case categories: null/empty, boundaries (min/max), special cases (unicode, whitespace), state (invalid transitions), errors (network, timeout)
- After generation: run tests, confirm they fail, verify helpful failure messages, check test independence
