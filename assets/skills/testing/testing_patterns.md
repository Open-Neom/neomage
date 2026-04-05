# Testing Patterns

Core testing patterns: factory functions, mocking strategies, and behavior-driven test organization.

- Test behavior not implementation: assert on visible outcomes, not mock call counts
- Factory pattern: create getMockX(overrides?) functions with sensible defaults for DRY test data
- Custom render function: wrap components with required providers (theme, store, router) for consistent setup
- AAA structure: Arrange (setup), Act (execute), Assert (verify) in every test
- Organize with describe blocks: group by component, then by scenario (rendering, interactions, edge cases)
- Clear mocks between tests with beforeEach; one behavior per test; descriptive test names
- Mocking: mock modules with jest.mock, access with jest.requireMock, prefer testing real behavior over mock verification
- Anti-patterns: testing mock behavior instead of real behavior, duplicated test data, vague test names, multiple responsibilities per test
