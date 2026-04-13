# Bash Defensive Patterns

Production-grade Bash scripting: strict mode, error handling, input validation, and safety practices.

- Always start with strict mode: set -euo pipefail; catches errors (-e), undefined vars (-u), and pipe failures (pipefail)
- Quote all variables: "$var" prevents word splitting and globbing; unquoted variables are the #1 source of bugs
- Validate inputs: check argument count, validate types and ranges, reject unexpected characters, use [[ ]] over [ ]
- Error traps: trap 'cleanup' EXIT for reliable cleanup; trap 'echo "Error line $LINENO"' ERR for debugging
- File operations: use mktemp for temp files, trap cleanup for deletion, check file existence before operations
- Command substitution: prefer $(command) over backticks; always quote the result: result="$(some_command)"
- Safe defaults: use ${var:-default} for defaults, ${var:?error message} to fail on missing required vars
- Avoid destructive commands without safeguards: use --dry-run flags, confirmation prompts, or explicit --force requirements
- Logging: write to stderr for diagnostics (>&2), use functions for consistent log format with timestamps
- Portability: specify #!/usr/bin/env bash, test on target OS, avoid bashisms if POSIX sh is required
- Never run as root unless strictly necessary; prefer sudo for specific commands over running entire scripts elevated
