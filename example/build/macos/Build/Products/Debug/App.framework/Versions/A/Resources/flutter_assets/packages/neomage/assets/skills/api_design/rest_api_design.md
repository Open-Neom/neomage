# REST API Design — Pragmatic Patterns

## Purpose

Design consistent, intuitive, and evolvable REST APIs.

## URL Structure

```
GET    /api/v1/users           → List users
GET    /api/v1/users/:id       → Get user
POST   /api/v1/users           → Create user
PUT    /api/v1/users/:id       → Replace user
PATCH  /api/v1/users/:id       → Partial update
DELETE /api/v1/users/:id       → Delete user
```

### Naming Rules
- Plural nouns: `/users` not `/user`
- Lowercase with hyphens: `/user-profiles` not `/userProfiles`
- No verbs in URLs: `/users` not `/getUsers`
- Nested resources: `/users/:id/orders` (max 2 levels deep)

## Response Format

```json
{
  "data": { ... },
  "meta": { "page": 1, "total": 42 },
  "errors": []
}
```

### Status Codes
| Code | Meaning | When to Use |
|------|---------|-------------|
| 200 | OK | Successful GET/PUT/PATCH |
| 201 | Created | Successful POST |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Invalid input |
| 401 | Unauthorized | Missing/invalid auth |
| 403 | Forbidden | Valid auth, no permission |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Duplicate, version conflict |
| 422 | Unprocessable | Valid syntax, invalid semantics |
| 429 | Too Many Requests | Rate limited |
| 500 | Server Error | Unhandled exception |

## Pagination

```
GET /users?page=2&per_page=20
GET /users?cursor=abc123&limit=20  (cursor-based — preferred for large datasets)
```

## Versioning

- URL path: `/api/v1/users` (simple, explicit)
- Header: `Accept: application/vnd.api+json;version=1` (cleaner URLs)

## Best Practices

- Use HTTPS everywhere
- Validate all inputs server-side
- Return consistent error format
- Include `Location` header for 201 responses
- Implement CORS for browser clients
- Rate limit all endpoints
- Document with OpenAPI/Swagger
