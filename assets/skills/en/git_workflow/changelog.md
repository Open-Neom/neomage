# Changelog Automation

Automate changelog generation from commits, PRs, and releases following Keep a Changelog and semantic versioning.

- Enforce conventional commit messages to enable automated changelog categorization
- Use commit types (feat, fix, chore, etc.) to auto-group entries under Added, Fixed, Changed sections
- Follow semantic versioning: breaking changes bump major, features bump minor, fixes bump patch
- Configure tooling to generate and publish release notes on tag or release events
- Avoid exposing secrets, internal details, or sensitive information in public release notes
- Review generated changelogs for accuracy and wording before publishing
- Label-based and commit-based strategies both work; choose one and enforce consistently
- Only use this for projects with an active release process and reliable commit history
