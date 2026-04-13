# Conventional Commit Messages

Write structured commit messages using the conventional commits format: `type(scope): subject`.

- Types: feat, fix, ref, perf, docs, test, build, ci, chore, style, meta, revert
- Subject line: imperative mood, capitalized first letter, no period, max 70 characters
- Body explains what and why (not how), using imperative present tense
- Footer references issues: `Fixes #1234` closes on merge, `Refs #1234` links without closing
- Breaking changes use `!` after type/scope and `BREAKING CHANGE:` in footer
- Each commit should be a single atomic, independently reviewable, stable change
- Branch naming follows `type/short-description` pattern matching commit type
- Never commit directly to main/master; always work on feature branches
- AI-generated changes include `Co-Authored-By: Claude <noreply@anthropic.com>` in footer
- Revert commits reference the original commit hash and explain the reason
