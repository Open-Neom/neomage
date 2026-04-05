# Async Python Patterns

Python asyncio, concurrent programming, and async/await for high-performance I/O-bound applications.

- Use async when I/O-bound (network, database, file); use sync + multiprocessing when CPU-bound
- Core primitives: async def for coroutines, await for suspension points, asyncio.run() as entry point
- Concurrency patterns: asyncio.gather() for parallel tasks, asyncio.create_task() for fire-and-forget, asyncio.Queue for producer-consumer
- Always set timeouts: asyncio.wait_for() wraps coroutines with deadlines; prevent indefinite hangs
- Backpressure: use bounded queues (asyncio.Queue(maxsize=N)) to prevent memory exhaustion under load
- Cancellation: tasks can be cancelled; handle CancelledError in finally blocks for cleanup
- Structured concurrency: use TaskGroup (Python 3.11+) for automatic cleanup of child tasks on failure
- Async libraries: httpx for HTTP, asyncpg for PostgreSQL, aiofiles for file I/O, aioredis for Redis
- Error handling: wrap await calls in try/except, propagate exceptions from gathered tasks, log failures without blocking
- Testing: use pytest-asyncio with @pytest.mark.asyncio; mock async functions with AsyncMock
- Never mix sync blocking calls in async code; use asyncio.to_thread() to bridge sync libraries into async context
