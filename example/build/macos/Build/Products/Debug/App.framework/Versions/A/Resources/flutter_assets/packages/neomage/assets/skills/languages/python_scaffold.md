# Python Project Scaffolding

Scaffold production Python projects: FastAPI, Django, libraries, and CLIs with modern tooling (uv, ruff, pytest).

- Package manager: uv for fast installs and virtual environments; pyproject.toml as the single config file
- Project types: FastAPI (async APIs), Django (full-stack/admin), Library (reusable packages), CLI (typer+rich)
- FastAPI structure: src/project/main.py, api/v1/endpoints/, core/, models/, schemas/, services/; layered separation
- Django structure: config/ for settings, apps per feature, fat models/thin views, use django-environ for config
- Library structure: src layout with py.typed marker, hatchling build backend, proper classifiers and exports
- CLI projects: typer for argument parsing, rich for terminal output, entry point in pyproject.toml [project.scripts]
- Testing: pytest with pytest-asyncio for async, httpx AsyncClient for API tests, conftest.py for shared fixtures
- Linting: ruff for both linting and formatting (replaces flake8+isort+black); configure in pyproject.toml
- Type hints: requires-python >=3.11, use built-in generics (list[T], dict[K,V]), Pydantic v2 for validation
- Dev tools: Makefile for common commands (dev, test, lint, format), .env.example for config docs, .gitignore for caches
