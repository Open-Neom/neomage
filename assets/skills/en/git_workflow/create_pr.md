# Create Pull Request

Create well-structured pull requests with clear descriptions explaining what changed and why.

- Verify all changes are committed and branch is up-to-date before creating the PR
- Analyze the full diff with `git diff base..HEAD` to understand scope before writing the description
- PR title follows conventional commit format: `type(scope): description`
- Description structure: what it does, why the change was made, alternatives considered, reviewer context
- Do not include test plan checklists or redundant diff summaries in the description
- Reference issues in the body: `Fixes #1234` to auto-close, `Refs #1234` to link
- One PR per feature or fix; avoid bundling unrelated changes
- Keep PRs small and reviewable; smaller PRs get faster, higher-quality reviews
- Use `--draft` flag for work-in-progress that needs early feedback
- Create PRs with `gh pr create`; use `gh api` for editing existing PRs
