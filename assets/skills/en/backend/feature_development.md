# Backend Feature Development
Orchestrate end-to-end feature delivery from requirements through architecture, implementation, testing, and deployment.
- Phase 1 Discovery: business analysis (user stories, acceptance criteria), technical architecture, security assessment
- Phase 2 Implementation: backend services with feature flags, frontend integration, data pipeline setup
- Phase 3 Testing: automated test suite (80%+ coverage), security validation (OWASP), performance optimization
- Phase 4 Deployment: CI/CD pipeline, observability (tracing, metrics, alerts, SLOs), documentation
- Methodologies: traditional, TDD (red-green-refactor), BDD (scenarios), DDD (bounded contexts)
- Deployment strategies: direct, canary (5% start), feature-flag, blue-green, A/B test
- Rollback strategy: feature flag disable (<1min), blue-green switch (<5min), full rollback (<15min)
- Every phase builds on outputs from the previous phase; maintain traceability throughout
- Validate data migrations and feature flags in staging before production
- Success: acceptance criteria met, tests pass, no critical vulnerabilities, monitoring operational
