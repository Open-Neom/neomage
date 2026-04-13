# API Mocking Framework
Create realistic mock APIs for development, testing, and demos that simulate real API behavior.
- Define the API contract, auth flows, error shapes, and latency expectations before building mocks
- Mock routes should cover happy paths, error scenarios, edge cases, and state transitions
- Provide deterministic fixtures by default with optional randomness for stress testing
- Clearly label mock endpoints to prevent accidental use against production
- Support scenario switching: different response sets for different test cases
- Include realistic latency simulation and rate limiting behavior in mocks
- Enable parallel development: frontend teams can work against mocks while backend builds real APIs
- Validate mock responses against the same schema as production for contract consistency
- Never reuse production secrets or real customer data in mock environments
- Document how to run the mock server, switch scenarios, and reset state
