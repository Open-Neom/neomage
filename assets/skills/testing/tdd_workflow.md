# TDD Workflow

Red-Green-Refactor cycle: write tests first, code second.

- RED: write a failing test that describes expected behavior; one assertion, clear name, must fail first
- GREEN: write the simplest code to pass (YAGNI); no optimization, no extra features
- REFACTOR: extract duplication, improve names, simplify structure -- all tests stay green
- Three Laws: only write production code to pass a failing test; only enough test to fail; only enough code to pass
- AAA Pattern for every test: Arrange (setup), Act (execute), Assert (verify)
- Test behavior not implementation; test names should describe what, not how
- Prioritize: happy path first, then error cases, edge cases, performance
- Anti-patterns: skipping RED, writing tests after, over-engineering in GREEN, multiple asserts per test
- If a test is hard to write, the design needs improvement -- listen to the test
