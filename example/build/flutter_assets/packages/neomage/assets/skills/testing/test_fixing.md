# Test Fixing

Systematically identify and fix all failing tests using smart error grouping strategies.

- Run full test suite first to identify all failures; analyze total count, error types, affected modules
- Group similar failures by: error type (ImportError, AttributeError, AssertionError), module/file, root cause
- Prioritize groups by impact count and dependency order (fix infrastructure before functionality)
- Fix order: infrastructure first (imports, deps, config), then API changes (signatures, renames), finally logic issues
- For each group: identify root cause, implement minimal focused fix, run subset to verify, then move on
- Use git diff to understand recent changes that likely caused the failures
- After all groups fixed: run complete test suite, verify no regressions, confirm coverage intact
- Never move to the next group until the current one passes completely
