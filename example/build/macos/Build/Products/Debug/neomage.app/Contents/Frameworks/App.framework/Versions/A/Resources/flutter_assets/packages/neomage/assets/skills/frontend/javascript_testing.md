# JavaScript Testing Patterns

Comprehensive JS/TS testing with Jest, Vitest, Testing Library, mocking, and TDD workflows.

- Test pyramid: many unit tests (fast, isolated), fewer integration tests (API/service boundaries), minimal E2E tests (user flows)
- Frameworks: Vitest (fast, ESM-native, Vite-aligned), Jest (mature ecosystem, wide adoption); both support TypeScript
- Component testing: React Testing Library with role-based queries (getByRole, getByText), fireEvent/userEvent for interactions
- Mocking: jest.fn()/vi.fn() for functions, jest.mock()/vi.mock() for modules, MSW for API mocking at the network level
- Fixtures: use factory functions over shared state, create fresh data per test, avoid test interdependence
- Async testing: use await/waitFor for async operations, handle promise rejections, test loading and error states
- TDD cycle: write failing test first (red), implement minimum code to pass (green), refactor while tests stay green
- Coverage: aim for meaningful coverage of critical paths, not 100% line coverage; test behavior, not implementation details
- Integration tests: test API endpoints with supertest/httpx, database operations with test containers, service interactions
- CI integration: run tests on every PR, parallelize test suites, fail builds on test failures, report coverage trends
