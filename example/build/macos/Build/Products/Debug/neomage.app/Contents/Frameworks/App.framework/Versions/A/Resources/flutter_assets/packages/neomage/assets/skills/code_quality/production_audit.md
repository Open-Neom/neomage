# Production Code Audit

Deep-scan an entire codebase line-by-line and systematically transform it to production-grade quality.

- Autonomously discover: scan all files, identify tech stack, understand architecture, map data flow
- Detect issues across: architecture (god classes, circular deps), security (injection, hardcoded secrets, weak hashing), performance (N+1, missing indexes, no caching), code quality (complexity, duplication, dead code), testing gaps, production readiness
- Fix automatically in priority order: critical security first, then high-impact performance, then quality
- Add production infrastructure: structured logging, error tracking, health checks, monitoring, rate limiting
- Verify after changes: run tests, measure performance improvements, confirm security compliance
- Target metrics: 80%+ test coverage, API response <200ms, OWASP Top 10 compliant, bundle <200KB gzipped
- Report with before/after metrics for every category
