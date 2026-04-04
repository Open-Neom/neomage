## 1.0.0

Complete migration from OpenClaude TypeScript (~385K LOC) to Flutter/Dart.
291 files, ~185K LOC. Verified on macOS and Web.

### Core
- Multi-provider support: Gemini, OpenAI, Anthropic, DeepSeek, Qwen, Ollama
- Native GeminiClient with query-param auth (not routed through OpenAI shim)
- Streaming chat with real-time token display
- Agentic tool execution loop with 31 tools
- Full context compaction system (strategies, token counting, hooks)
- 24 builtin slash commands
- MCP (Model Context Protocol) client
- Plugin system with install/uninstall/lifecycle management
- Skills framework with registry
- Hook system (lifecycle, permissions, pre/post compact)
- Remote session management (HTTP + WebSocket with reconnection)

### UI
- 30 widgets ported from OpenClaude components
- 8 screens: chat, onboarding, settings, splash, doctor, MCP panel, session browser, Ollama setup
- Vim mode emulation
- Keybinding system with resolver
- Dark/light Material 3 theme with extended ARGB colors
- Markdown rendering with syntax highlighting
- Command palette (Ctrl+K)

### Infrastructure
- Sint framework for state management, DI, navigation
- SintSentinel circuit breaker + centralized Logger
- flutter_secure_storage for API keys (Keychain on macOS)
- Provider-agnostic — no model-specific references
- Cross-platform: macOS, Web (verified), iOS, Android, Linux, Windows
- App icons generated for all platforms
- 160/160 pub.dev score structure

### Architecture
- Extension types for branded IDs (SessionId, AgentId)
- Sealed classes for unions (ContentBlock, PermissionDecision, etc.)
- Barrel file exports with show/hide for clean API surface
- Platform abstraction layer (web + native IO)

## 0.1.0

- Initial release of NeomClaw (neom_claw)
- Multi-provider support: Gemini (default), Qwen, OpenAI, DeepSeek, Anthropic, Ollama
- Streaming chat with real-time token display
- Agentic tool execution loop: bash, file read/write/edit, grep, glob
- Image and file attachments with preview
- Ollama local model management: auto-discovery, download, delete, test
- MCP (Model Context Protocol) client panel
- Settings with provider configuration and connection testing
- Onboarding flow with provider selection
- Cross-platform: macOS, Linux, Windows, Web, iOS, Android
- Dark/light Material 3 theme
- Markdown rendering with syntax highlighting
- Command palette (Ctrl+K)
- Session management and conversation history
- OpenAI-compatible shim for provider-agnostic architecture
