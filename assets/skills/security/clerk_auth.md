# Clerk Authentication

Patterns for Clerk auth in Next.js: middleware, server components, organizations, and webhooks.

- ClerkProvider wraps the app root to provide auth context; SignIn/SignUp/UserButton are pre-built components
- Route protection: single middleware.ts at project root using clerkMiddleware and createRouteMatcher
- Use auth.protect() for explicit route protection; centralize all auth logic in middleware, not in pages
- Server components: auth() returns userId/sessionId/orgId/claims; currentUser() returns the full User object
- Both auth() and currentUser() require clerkMiddleware to be configured or they will fail silently
- Organization support: use orgId from auth() for multi-tenant access control and data scoping
- Webhooks: verify Clerk webhook signatures before processing; use svix for verification
- Token access: use getToken() for custom JWT templates when calling external APIs
- Always handle the unauthenticated state gracefully; redirect to sign-in rather than showing errors
