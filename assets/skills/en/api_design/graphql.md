# GraphQL
Build GraphQL APIs at scale with proper schema design, performance safeguards, and client integration.
- The schema IS the API contract and documentation -- design it carefully with intentional nullability
- CRITICAL: use DataLoader for every resolver that touches a database to prevent N+1 queries
- CRITICAL: limit query depth and complexity to prevent clients from crafting DoS queries
- Disable introspection in production to avoid exposing your entire schema
- Authorize in resolvers, not just schema directives; implement field-level authorization
- Non-null field failures nullify the entire parent -- design nullability to match error semantics
- Implement query cost analysis to treat expensive queries differently from cheap ones
- Use persisted queries (APQ) for production to lock down allowed operations
- Clean up subscriptions properly to prevent memory leaks and connection exhaustion
- Works well with: backend services, PostgreSQL, Next.js, React patterns
