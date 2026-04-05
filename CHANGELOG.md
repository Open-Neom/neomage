## 1.0.0

Neomage: multi-provider AI agent engine for Flutter, restructured as a pub.dev package.

### Package (lib/)

- **Multi-provider API clients**: Gemini (native), OpenAI, Anthropic, DeepSeek, Qwen, Ollama — all via a unified `ApiProvider` interface
- **Streaming**: SSE parser conforming to W3C EventSource spec, typed stream events (`TextDelta`, `ThinkingDelta`, `ToolUseStart`, etc.)
- **Agentic tool system**: 31 built-in tools (Bash, FileRead/Write/Edit, Grep, Glob, WebSearch, Agent, SendMessage, TodoWrite, etc.)
- **Bash security**: 20+ validation checks — command substitution, IFS injection, obfuscated flags, dangerous variables, redirection analysis
- **Query engine**: Multi-turn agentic conversation loop with automatic tool execution
- **Context compaction**: Token-aware conversation summarization with configurable strategies
- **Skills framework**: 283 loadable markdown skills across 40+ categories
- **Personality system**: 10 modular personality files (Identity, Cognition, Agency, Memory, etc.) assembled into dynamic system prompts
- **MCP client**: Model Context Protocol support for external tool servers
- **Retry with backoff**: Configurable exponential backoff with 429/529 awareness
- **Domain models**: `Message`, `ContentBlock` (sealed), `ToolDefinition`, `TokenUsage`, branded IDs (`SessionId`, `AgentId`)
- **Error classification**: `ApiError` with typed categories (rateLimited, authenticationError, promptTooLong, etc.)
- **Platform abstraction**: dart:io stubs for web compatibility
- **Sint framework**: State management, DI, navigation via Sint + SintSentinel

### Example App (example/)

- Full AI coding assistant: 8 screens (chat, onboarding, settings, Ollama setup, MCP panel, doctor, session browser, splash)
- 30+ widgets (input bar, message renderer, markdown preview, diff view, command palette, permission dialogs, etc.)
- Vim mode, keybinding system, dark/light Material 3 theme
- Skills browser with search, categories, and two loading modes (session visible / context silent)
- Localization: English + Spanish
- Cross-platform: macOS, Web, Linux, Windows, iOS, Android

### Infrastructure

- Package/app split: reusable logic in `lib/`, full app in `example/`
- Barrel exports with `show`/`hide` for clean API surface
- 0 analysis errors, pub.dev dry-run validated

## 0.1.0

- Initial development release
- Multi-provider support: Gemini, OpenAI, Anthropic, DeepSeek, Qwen, Ollama
- Streaming chat, agentic tool execution, MCP client
- Cross-platform Flutter app
