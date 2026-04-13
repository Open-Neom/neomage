# Complete Git Workflow

Orchestrate a full git workflow from code review through PR creation with quality gates at each phase.

- Phase 1 (Pre-Commit): Review changes for code quality, security, performance, and breaking changes
- Phase 2 (Testing): Run unit, integration, and e2e tests; analyze coverage gaps for critical paths
- Phase 3 (Commit): Categorize changes by conventional commit type, generate proper commit messages
- Phase 4 (Branch/Push): Validate branch naming, check for conflicts, scan for secrets, verify CI readiness
- Phase 5 (PR): Generate comprehensive PR description, configure labels, reviewers, and merge strategy
- Branch naming: `(feature|bugfix|hotfix|docs|chore)/ticket-id-brief-description`
- Keep PRs under 400 lines for effective review; address review comments within 24 hours
- Success criteria: all tests pass, no critical issues, conventional commits, no merge conflicts
- Rollback plan: git revert for immediate revert, feature flags for gradual rollback, hotfix branch for critical issues
