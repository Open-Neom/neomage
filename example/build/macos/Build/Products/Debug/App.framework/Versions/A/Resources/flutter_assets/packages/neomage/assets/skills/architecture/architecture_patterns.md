# Architecture Patterns
Proven backend patterns including Clean Architecture, Hexagonal Architecture, and Domain-Driven Design.
- Clean Architecture: dependencies point inward, domain at center, frameworks at edges
- Hexagonal Architecture: ports define interfaces, adapters implement them for external systems
- DDD: identify bounded contexts, aggregate roots, ubiquitous language within each context
- Define module boundaries with clear interfaces and strict dependency rules between layers
- Choose pattern based on domain complexity: simple CRUD rarely needs DDD or hexagonal
- Migration path: start monolithic, extract modules, then services when boundaries are proven
- Ensure testability by depending on abstractions, not concretions at every boundary
- Avoid mixing patterns: pick one primary architecture and apply it consistently
- Validate with checklists: boundary integrity, dependency direction, single responsibility
- When refactoring, clarify domain boundaries and scalability targets before selecting patterns
