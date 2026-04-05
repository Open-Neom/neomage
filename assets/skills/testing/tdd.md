# Test-Driven Development

Write the test first, watch it fail, write minimal code to pass. No exceptions.

- Iron Law: NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST. Code before test? Delete it. Start over.
- RED: write one minimal test showing expected behavior; clear name, real code (mocks only if unavoidable)
- Verify RED: run test, confirm it fails for the right reason (missing feature, not typo)
- GREEN: write simplest code to pass; don't add features, don't refactor, don't optimize
- Verify GREEN: all tests pass, output pristine (no errors or warnings)
- REFACTOR: remove duplication, improve names, extract helpers; keep tests green
- Tests written after code pass immediately -- proving nothing. Test-first forces you to see the failure.
- If test is hard to write, the design needs simplification. Listen to the test.
- Rationalizations to reject: "too simple to test", "I'll test after", "TDD will slow me down", "just this once"
- Debugging integration: bug found? Write failing test reproducing it, then fix. Never fix bugs without a test.
