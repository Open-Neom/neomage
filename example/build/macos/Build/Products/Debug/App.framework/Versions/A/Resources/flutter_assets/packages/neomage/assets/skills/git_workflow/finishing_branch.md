# Finishing a Development Branch

Guide completion of development work by verifying tests and presenting structured integration options.

- Always verify all tests pass before presenting any completion options
- If tests fail, stop immediately and fix them before proceeding
- Present exactly four options: merge locally, push and create PR, keep as-is, or discard
- For local merge: switch to base branch, pull latest, merge, re-verify tests, delete feature branch
- For PR creation: push branch with `-u`, create PR with summary and test plan
- For discard: require explicit typed "discard" confirmation before deleting any work
- Clean up git worktrees for merge and discard options; preserve for PR and keep-as-is
- Never force-push without explicit user request
- Never proceed with failing tests or merge without verifying tests on the result
