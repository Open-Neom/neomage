# MCP Builder

Create high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services.

- Recommended stack: TypeScript with Streamable HTTP transport (stateless JSON) for remote, stdio for local
- Quality is measured by how well the server enables LLMs to accomplish real-world tasks
- Tool naming: use consistent prefixes and action-oriented names (e.g., github_create_issue, github_list_repos)
- Tool descriptions must be concise and guide agents to the right tool quickly
- Input schemas: use Zod (TypeScript) or Pydantic (Python) with constraints, descriptions, and examples
- Define outputSchema for structured data; return both text content and structured data when possible
- Tool annotations: set readOnlyHint, destructiveHint, idempotentHint, openWorldHint for each tool
- Error messages must be actionable: guide agents toward solutions with specific next steps
- Support pagination for list operations; return focused, relevant data to manage context efficiently
- Phase workflow: deep research/planning -> implementation -> review/test -> create evaluations (10 complex QA pairs)
