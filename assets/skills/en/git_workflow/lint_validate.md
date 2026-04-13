# Lint and Validate

Mandatory quality control: run linting and static analysis after every code change before considering work done.

- Node.js/TypeScript: `npm run lint` for style, `npx tsc --noEmit` for types, `npm audit` for security
- Python: `ruff check --fix` for linting, `mypy` for types, `bandit -r -ll` for security
- The quality loop: write code, run audit, analyze report, fix issues, repeat until clean
- If lint fails: fix style/syntax issues immediately before proceeding
- If type checking fails: correct type mismatches before any other work
- If no linting tool is configured: check for `.eslintrc`, `tsconfig.json`, or `pyproject.toml` and suggest setup
- No code should be committed or reported as done without passing all configured checks
- Treat this as a non-negotiable gate, not an optional step
