# Software Architecture
Quality-focused development guidance based on Clean Architecture and Domain-Driven Design principles.
- Use early return pattern over nested conditions; avoid code duplication through reusable functions
- Decompose long functions (>80 lines) and files (>200 lines) into smaller, focused units
- Library-first: always search for existing solutions before writing custom code
- Custom code justified only for: unique business logic, performance-critical paths, security-sensitive code
- Follow DDD: ubiquitous language, separated domain entities, framework-independent business logic
- Naming: avoid generic names (utils, helpers, common); use domain-specific names (OrderCalculator)
- Separation of concerns: never mix business logic with UI; keep queries out of controllers
- Anti-patterns to avoid: NIH syndrome, generic naming dumps, deep nesting (max 3 levels)
- Keep functions under 50 lines, files under 200 lines; proper error handling with typed catches
- Every line of custom code is a liability needing maintenance, testing, and documentation
