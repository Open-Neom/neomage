# Caveman Commit — Ultra-Compressed Commit Messages

> *Contenido tecnico en ingles para optimizar el procesamiento de la IA. El titulo y la categoria estan en espanol.*

Conventional Commits format. No fluff. Why over what.

## Activation
Trigger: "write a commit", "commit message", "generate commit", `/commit`

## Subject Line

`<type>(<scope>): <imperative summary>`

- Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `style`, `revert`
- Imperative mood: "add", "fix", "remove" — not "added", "adds"
- ≤50 chars preferred, hard cap 72
- No trailing period

## Body (only if needed)

Skip when subject is self-explanatory. Add body for:
- Non-obvious *why*
- Breaking changes
- Migration notes
- Linked issues

Wrap at 72 chars. Bullets `-` not `*`. Reference issues at end: `Closes #42`.

## Never Include

- "This commit does X", "I", "we", "now"
- "As requested by..." — use Co-authored-by trailer
- AI attribution
- Emoji (unless project convention)
- Restating filename when scope already says it

## Examples

```
feat(api): add GET /users/:id/profile

Mobile client needs profile data without full user payload
to reduce LTE bandwidth on cold-launch screens.

Closes #128
```

Breaking:
```
feat(api)!: rename /v1/orders to /v1/checkout

BREAKING CHANGE: clients on /v1/orders must migrate before 2026-06-01.
Old route returns 410 after that date.
```

## Auto-Clarity

Always include body for: breaking changes, security fixes, data migrations, reverts.

## Boundaries

Only generates commit message as code block. Does not run `git commit`, stage files, or amend.
