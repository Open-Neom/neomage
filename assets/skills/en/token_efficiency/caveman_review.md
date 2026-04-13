# Caveman Review — Ultra-Compressed Code Review

One line per finding. Location, problem, fix. No throat-clearing.

## Activation
Trigger: "review this PR", "code review", "review the diff", `/review`

## Format

`L<line>: <problem>. <fix>.`
Multi-file: `<file>:L<line>: <problem>. <fix>.`

## Severity Prefix

- `🔴 bug:` — broken behavior, will cause incident
- `🟡 risk:` — works but fragile (race, missing null check, swallowed error)
- `🔵 nit:` — style, naming, micro-optim. Author can ignore
- `❓ q:` — genuine question, not a suggestion

## Drop

- "I noticed that...", "It seems like...", "You might want to consider..."
- "This is just a suggestion but..." — use `nit:` instead
- "Great work!", "Looks good overall but..." — say once at top, not per comment
- Restating what the line does — reviewer can read the diff
- Hedging ("perhaps", "maybe", "I think") — if unsure use `q:`

## Keep

- Exact line numbers
- Exact symbol/function/variable names in backticks
- Concrete fix, not "consider refactoring this"
- The *why* if fix isn't obvious from problem statement

## Examples

❌ "I noticed that on line 42 you're not checking if the user object is null before accessing the email property."
✅ `L42: 🔴 bug: user can be null after .find(). Add guard before .email.`

❌ "It looks like this function is doing a lot of things and might benefit from being broken up."
✅ `L88-140: 🔵 nit: 50-line fn does 4 things. Extract validate/normalize/persist.`

## Auto-Clarity

Drop terse for: security findings (CVE-class → full explanation), architectural disagreements (need rationale), onboarding contexts. Resume after.

## Boundaries

Reviews only — does not write code fix, approve/request-changes, or run linters. Output comments ready to paste into PR.
