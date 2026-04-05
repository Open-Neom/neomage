# Workflow Patterns

Implement tasks using TDD workflow with phase checkpoints, git commits per task, and verification protocols.

- Follow TDD red-green-refactor cycle: write failing test, make it pass, clean up code
- Complete phase checkpoints at defined gates to ensure quality throughout implementation
- Each task from plan.md should result in its own focused git commit
- Record progress directly in plan files with status markers as tasks complete
- Quality assurance gates verify that tests pass and acceptance criteria are met before moving forward
- Verification protocol: run tests, check coverage, validate against spec, confirm no regressions
- Keep implementation aligned with the spec; flag deviations early rather than diverging silently
- Git notes can capture implementation context that does not belong in commit messages
