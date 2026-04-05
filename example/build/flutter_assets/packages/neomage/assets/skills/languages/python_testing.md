# Python Testing Patterns

Robust Python testing with pytest: fixtures, mocking, parameterization, TDD, and async test strategies.

- pytest is the standard: auto-discovery, rich assertions, powerful fixture system, extensive plugin ecosystem
- Test pyramid: many fast unit tests, fewer integration tests (API/DB), minimal E2E tests for critical user flows
- Fixtures: use conftest.py for shared fixtures, factory functions over shared mutable state, scope (function/module/session)
- Mocking: unittest.mock.patch for replacing dependencies, MagicMock for objects, AsyncMock for async functions
- Parameterization: @pytest.mark.parametrize for testing multiple inputs; use ids parameter for readable test names
- Async testing: pytest-asyncio with @pytest.mark.asyncio, httpx.AsyncClient for FastAPI, asyncio_mode="auto" in config
- TDD cycle: write failing test (red), implement minimum to pass (green), refactor while green; commit at each green
- Database testing: use test fixtures for setup/teardown, factory_boy for model factories, transactions for isolation
- Property-based testing: hypothesis for generating edge-case inputs automatically; finds bugs manual tests miss
- CI integration: run on every PR, fail on test failures, track coverage trends, parallelize with pytest-xdist
- Test behavior not implementation: assert on outputs and side effects, not internal state; tests should survive refactoring
