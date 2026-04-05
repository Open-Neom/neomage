# Backend Development Guidelines
Opinionated Node.js + Express + TypeScript standards: layered architecture, validation, observability, testing.
- Mandatory layer order: Routes -> Controllers -> Services -> Repositories -> Database; no skipping
- Routes only route (zero logic); controllers coordinate via BaseController; services contain business rules
- All external input validated with Zod schemas: request bodies, query params, route params, webhooks
- All errors go to Sentry; no console.log, no silent failures, no swallowed errors
- Use unifiedConfig as the only config source; never access process.env directly
- Dependency injection: services receive dependencies via constructor for testability
- Prisma client never used directly in controllers; repositories encapsulate all database access
- All async route handlers wrapped with asyncErrorWrapper to prevent unhandled rejections
- Required tests: unit tests for services, integration tests for routes, repository tests for complex queries
- Anti-patterns (immediate rejection): business logic in routes, direct Prisma in controllers, missing validation
