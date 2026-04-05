# Iterate PR Until CI Passes

Continuously fix CI failures and address review feedback in a loop until all checks are green.

- Start by checking CI status with `gh pr checks`; wait for pending bot checks before acting
- Gather feedback from three sources: CI check results, human review comments, and bot comments
- Always read actual failure logs with `gh run view <id> --log-failed`; never assume from check names alone
- Validate each piece of feedback: verify the issue is real, check if already fixed, skip invalid concerns
- Make minimal, targeted fixes; only change what is actually broken
- Commit fixes with descriptive messages, push, then watch CI with `gh pr checks --watch`
- Repeat the check-fix-push cycle until all required checks pass and no unaddressed feedback remains
- Ask for help after 3 failed attempts on the same issue (likely flaky test or deeper problem)
- Stop immediately if branch needs rebase or no PR exists for the current branch
