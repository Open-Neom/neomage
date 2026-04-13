# Python Performance Optimization

Profile and optimize Python code: CPU profiling, memory optimization, and implementation best practices.

- Always profile before optimizing: use cProfile for CPU hotspots, memory_profiler for memory usage, line_profiler for line-level timing
- Data structures matter: dict/set for O(1) lookups, deque for O(1) append/popleft, use slots on classes to reduce memory
- Generator expressions over list comprehensions when iterating once: (x for x in items) avoids materializing the full list
- String concatenation: use str.join() for many strings, f-strings for formatting; avoid repeated += in loops
- Database optimization: batch queries, use select_related/prefetch_related (Django), eager loading (SQLAlchemy), add indexes
- I/O optimization: use async for concurrent I/O, connection pooling for databases, streaming for large files
- CPU-bound work: multiprocessing.Pool for parallelism, numpy/pandas for vectorized operations, consider Cython or Rust extensions
- Caching: functools.lru_cache for pure function memoization, Redis for distributed caching, cache invalidation strategy
- Memory leaks: watch for circular references, use weakref where appropriate, profile with tracemalloc
- Algorithmic improvements yield the biggest gains: prefer O(n) over O(n^2) before micro-optimizing constants
