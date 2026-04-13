# Python Patterns

Python development principles and decision-making: framework selection, async vs sync, types, and architecture.

- Framework selection: FastAPI for APIs/microservices, Django for full-stack/CMS/admin, Flask for simple/learning projects
- Async vs sync golden rule: I/O-bound (network, DB, files) uses async; CPU-bound uses sync + multiprocessing
- Never mix sync blocking calls inside async code; never force async for CPU work
- Async library choices: httpx (HTTP), asyncpg (PostgreSQL), aioredis (Redis), aiofiles (file I/O), SQLAlchemy 2.0 async
- Type hints strategy: always type function parameters, return types, class attributes, public APIs; skip local variables
- Pydantic v2: use for API request/response models, configuration/settings, data validation; integrates natively with FastAPI
- Project structure: small (flat files), medium (app/ with routes/services/models/schemas), large (src/ with feature modules)
- FastAPI specifics: async def for I/O operations, def for blocking (auto-threadpooled); use Depends() for injection
- Django best practices: fat models/thin views, select_related for FKs, prefetch_related for M2M, avoid N+1 queries
- Error handling: custom exception classes, consistent error format (code + message + details), never expose stack traces
- Background tasks: FastAPI BackgroundTasks for simple, Celery/ARQ for distributed/persistent, choose based on persistence needs
- Anti-patterns: defaulting to Django for simple APIs, putting business logic in routes, skipping types on public APIs
