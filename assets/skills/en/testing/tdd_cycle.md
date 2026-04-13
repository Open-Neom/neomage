# TDD Cycle

Execute comprehensive TDD with strict red-green-refactor discipline and coverage validation at each phase.

- Coverage thresholds: 80% line, 75% branch, 100% critical paths
- Refactoring triggers: cyclomatic complexity >10, method >20 lines, class >200 lines, duplicate blocks >3 lines
- RED phase: write ALL failing tests before implementation; verify each fails for the right reason (missing behavior, not syntax)
- GREEN phase: implement minimal code to pass; no extra code beyond test requirements; no tests modified to pass
- REFACTOR phase: apply SOLID, remove duplication, improve naming; tests must stay green throughout
- Integration: write failing integration tests after unit cycle; test component interactions and data flow
- If TDD discipline breaks: STOP immediately, rollback to last valid state, resume from correct phase
- Anti-patterns: implementation before tests, tests that already pass, skipping refactor, modifying tests to pass
