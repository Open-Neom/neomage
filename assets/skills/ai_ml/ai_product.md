# AI Product Development

Ship LLM-powered features to production that users trust -- demos are easy, production is hard.

- Treat prompts as code: version control, regression testing, A/B testing, performance tracking
- Always validate LLM outputs: use function calling or JSON mode with schema validation, never trust raw text
- Stream responses to reduce perceived latency and show progress to users
- Anti-patterns: demo-ware (impressive demo, broken production), context window stuffing (expensive, slow, noisy), unstructured output parsing (breaks randomly)
- Sanitize all user input before including in prompts; implement defense layers against prompt injection
- Monitor LLM API costs per request; set budgets and alerts before costs spiral
- Implement fallback strategies: model fallbacks, cached responses, graceful degradation when APIs fail
- Use async patterns for LLM calls; never block request handlers on synchronous LLM responses
- Verify factual claims from LLM responses against ground truth when accuracy matters
- Calculate tokens before sending to avoid context window limits; compress and filter for relevance
