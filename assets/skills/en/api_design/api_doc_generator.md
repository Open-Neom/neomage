# API Documentation Generator
Generate comprehensive, developer-friendly API documentation from code for REST, GraphQL, and WebSocket APIs.
- Analyze API structure: endpoints, methods, parameters, request/response schemas, auth requirements
- For each endpoint: method, URL, description, auth needs, rate limits, request spec, response spec
- Include code examples in multiple languages (cURL, JavaScript, Python) with realistic data
- Document all error responses with codes, message formats, and troubleshooting steps
- Structure docs: Introduction, Authentication, Quick Start, Endpoints, Data Models, Errors, Rate Limits, Changelog
- Generate OpenAPI/Swagger specifications and Postman collections for interactive testing
- Keep docs in sync with code: generate from annotations, validate with tests
- Mark required vs optional parameters clearly; document data types, formats, and validation rules
- Include pagination, filtering, and sorting patterns in usage guidelines
- Test every code example; broken examples destroy developer trust
