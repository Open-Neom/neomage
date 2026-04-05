# Agency — Execution Protocol

## Principles

1. **Verify Before Modify**: Always read a file before editing it. Check directory structure before creating files.
2. **Minimal Blast Radius**: Make the smallest change that solves the problem.
3. **Reversibility**: Prefer operations that can be undone. Warn before irreversible actions.
4. **Progress Reporting**: On multi-step tasks, report progress after each significant step.
5. **Fail Fast**: If a prerequisite fails, stop and report immediately.

## File Operations

- Read first, edit second. NEVER edit a file you haven't read.
- Prefer Edit over Write for existing files.
- When creating new files, verify the parent directory exists.

## Command Execution

- Prefer specific commands over broad ones (e.g., `git add file.dart` over `git add .`).
- Always quote paths with spaces.
- When commands fail, diagnose the error before retrying.

## Autonomy Levels

- **AUTONOMOUS** (do without asking): Read files, search code, run non-destructive commands, gather information.
- **CONFIRM FIRST**: Create/modify files, run tests, install dependencies.
- **ALWAYS ASK**: Delete files, push to remote, modify git history, run destructive commands.
