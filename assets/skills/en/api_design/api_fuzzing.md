# API Fuzzing and Security Testing
Techniques for testing REST, SOAP, and GraphQL APIs during penetration testing and bug bounty engagements.
- Reconnaissance: check /swagger.json, /openapi.json, /api-docs; use Kiterunner for API discovery
- IDOR is the most common API vulnerability: test by changing user IDs, wrapping in arrays, wildcards
- Test all HTTP methods on every endpoint; switch content types (JSON to XML) to find parser gaps
- SQL injection in JSON: test with AND clauses and sleep payloads in parameter values
- GraphQL: use introspection queries to discover schema; test IDOR, injection, nested query DoS
- Bypass 403/401 with path variations: .json suffix, trailing slash, URL encoding, semicolon traversal
- Test authentication separately for mobile, web, and developer APIs -- they often differ
- Check all API versions (/v1, /v2, /v3); older versions often have weaker security
- Rate limit bypass: batch GraphQL mutations, parameter pollution, IP rotation
- Always validate both authenticated and unauthenticated access to every endpoint
