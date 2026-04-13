# AI Wrapper Product

Build products where AI APIs are the engine, not the gimmick -- solve specific problems people will pay for.

- Wrapper stack: User Input -> Validation/Sanitization -> Prompt Template + Context -> AI API -> Output Parsing/Validation -> User Response
- Differentiate through domain expertise, specialized UX, workflow integration, and output post-processing -- not just "ChatGPT but different"
- Model selection: match model tier (GPT-4o, Claude Sonnet, Haiku) to task complexity; use cheapest model that meets quality bar
- Track every API call: log input/output tokens, calculate cost per request, set monthly limits per user for profitability
- Cost reduction: use cheaper models (10-50x savings), limit output tokens, cache common queries, batch similar requests
- Force structured output with JSON schemas; parse with fallback extraction; validate before returning to user
- Production prompt patterns: system prompt for role/format/tone, user prompt template with variable injection, output format spec
- Anti-patterns: thin wrapper (no differentiation), ignoring costs until scale, no output validation
- Handle rate limits with queues and exponential backoff; implement streaming for perceived speed
- Price with margin: know your cost per user interaction and build pricing around it
