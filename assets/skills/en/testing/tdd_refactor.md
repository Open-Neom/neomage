# TDD Refactor Phase

Improve code quality with confidence using the comprehensive test safety net established in red-green phases.

- Pre-assessment: verify green baseline, analyze code smells, measure current performance
- Smell detection: duplicated code, long methods, large classes, feature envy, primitive obsession, dead code
- Apply SOLID: single responsibility, open/closed, Liskov substitution, interface segregation, dependency inversion
- Techniques: extract method/variable/interface, rename for clarity, replace conditional with polymorphism, introduce null object
- Make small atomic changes; run tests after each modification; commit after each successful refactoring
- Keep refactoring separate from behavior changes; use scaffolding when needed
- Advanced patterns: Strangler Fig (gradual replacement), Branch by Abstraction, Mikado Method
- Recovery: if tests fail, immediately revert last change and apply smaller incremental steps
