# Address GitHub PR Comments

Systematically address review comments and feedback on open pull requests using the gh CLI.

- Fetch all PR comments with `gh pr view --comments` to see the full conversation
- Categorize comments by type: code changes, clarifications, style fixes, and blocking issues
- Always read surrounding code context before applying any fix suggested by a reviewer
- Confirm with the user which comments to address first when there are many threads
- After applying fixes, respond to each resolved thread with `gh pr comment` noting the resolution
- Verify `gh auth status` before starting any PR interaction to avoid auth failures
- Apply fixes in a single focused commit referencing the review feedback
