# Git Workflow — Best Practices

## Purpose

Use Git effectively for version control, collaboration, and safe code delivery.

## Commit Practices

### Conventional Commits
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`

### Commit Rules
- Atomic commits: one logical change per commit
- Present tense: "add feature" not "added feature"
- Under 72 characters for the subject line
- Body explains WHY, not WHAT (the diff shows what)

## Branch Strategy

### Git Flow (for releases)
- `main` — production-ready
- `develop` — integration branch
- `feature/*` — new features
- `hotfix/*` — production fixes
- `release/*` — release preparation

### Trunk-Based (for CI/CD)
- `main` — always deployable
- Short-lived feature branches (1-3 days max)
- Feature flags for incomplete features

## Safety Checklist

- [ ] Never force push to `main`/`develop`
- [ ] Review diffs before committing (`git diff --staged`)
- [ ] Don't commit `.env`, credentials, or large binaries
- [ ] Use `.gitignore` for build artifacts
- [ ] Sign commits when working on security-sensitive projects

## Useful Commands

```bash
# Undo last commit (keep changes)
git reset --soft HEAD~1

# See what changed between branches
git diff main...feature-branch

# Find when a bug was introduced
git bisect start && git bisect bad && git bisect good <sha>

# Interactive rebase (clean up before PR)
git rebase -i main

# Stash with message
git stash push -m "WIP: refactoring auth"
```
