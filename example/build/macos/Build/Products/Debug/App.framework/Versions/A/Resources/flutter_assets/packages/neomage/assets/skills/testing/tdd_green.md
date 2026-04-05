# TDD Green Phase

Implement the minimal code needed to make failing tests pass -- nothing more.

- Review failing tests and identify the smallest change that makes the next test pass
- Implement only what is needed to satisfy the test assertion; resist adding features
- Run tests after each change to confirm progress toward green
- YAGNI principle: you aren't gonna need it; don't optimize, don't generalize
- Record shortcuts or known debt to address in the refactor phase
- Never bypass or weaken tests to make them pass
- Keep changes scoped exclusively to the failing behavior
- Once green, proceed to refactor phase -- never ship green-phase code as-is
