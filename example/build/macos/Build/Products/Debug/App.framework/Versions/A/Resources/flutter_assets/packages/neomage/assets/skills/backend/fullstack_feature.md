# Full-Stack Feature Orchestration
Coordinate full-stack feature development across database, backend, frontend, and infrastructure layers.
- Phase 1 Design: database architecture first, then backend service architecture, then frontend components
- Phase 2 Implementation (parallel): backend services, frontend components, database optimization
- Phase 3 Integration: API contract testing (Pact/Dredd), E2E testing (Playwright/Cypress), security audit
- Phase 4 Operations: CI/CD with quality gates, observability (OpenTelemetry, Prometheus), performance optimization
- Follow API-first principles: the spec drives both backend implementation and frontend consumption
- Feature flags enable progressive rollout and instant rollback without redeployment
- Use correlation IDs across all services for distributed tracing
- Success criteria: contract tests pass, E2E covers critical journeys, security audit clean, SLOs met
- Document all architectural decisions in ADRs; maintain consistent error handling across services
- Zero-downtime deployment capability verified; rollback procedures tested
