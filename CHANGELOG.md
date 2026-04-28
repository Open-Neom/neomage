## 1.3.0 — 2026-04-28

- **`GeminiRealtimeClient` + `GeminiRealtimeEvent`** (`lib/realtime/`):
  pure-Dart client for the Gemini Live (`BidiGenerateContent`) WebSocket
  API. Streams audio bidirectionally over a single socket so apps can
  build real-time voice conversations without TTS round-trips.
  - **Audio formats**: input PCM 16-bit 16 kHz mono LE; output PCM 16-bit
    24 kHz mono LE. Caller wires its own mic (`record`, Web Audio API,
    etc.) and speaker (`flutter_pcm_sound`, etc.); the client only does
    bytes-in/bytes-out so `neomage` stays platform-agnostic.
  - **Sealed `GeminiRealtimeEvent` hierarchy**: `GeminiSetupComplete`,
    `GeminiAudioOut`, `GeminiTextDelta`, `GeminiTurnComplete`,
    `GeminiInterrupted`, `GeminiRealtimeError`. Pattern-match in
    consumers — no untyped JSON needed.
  - **Test-first**: 14 unit tests via an injectable `WebSocketChannel`
    fake. Covers setup envelopes, system instructions, base64 PCM
    encoding, text turns, server-content dispatch (audio + text +
    interrupt + turn-complete + error).
- New direct dependency: `web_socket_channel: ^3.0.0`.

## 1.2.0 — 2026-04-27
- **Switch `neom_ollama` to hosted dep**: was `path: ../neom_modules/ai/
  neom_ollama` during local development; now consumes `neom_ollama: ^1.2.0`
  from pub.dev. This unblocks the package for `flutter pub publish` (path
  deps are forbidden on pub.dev) and brings in:
  - Hardware profiling (`HardwareProfile.detect()`).
  - Thinking trace parsing (Qwen3, DeepSeek-R1, QwQ, gpt-oss).
  - **`PlainTextToolCallParser`** — recovers tool calls embedded as text
    (LMStudio bracket form, Hermes / Qwen `<tool_call>` tag, fenced JSON,
    bare-JSON last-resort) for local models that don't always populate
    structured `tool_calls`.
- **Skills localization redesign**: replace the `skills/es/` folder of 348
  duplicate-with-disclaimer markdowns with a single `skill_meta_es.json`
  catalog. All LLM-facing skill bodies now load from `skills/en/` only; the
  Spanish-facing UI descriptions (short taglines, MX market order) live in
  the meta catalog. Saves ~1.5 MB in the asset bundle and removes a source
  of drift between locales.
- Delete 54 `assets/skills/es/...` entries from `pubspec.yaml` flutter
  assets section.
- Add `skill_meta_es.json` asset declaration (54 categories + 164 curated
  skill descriptions with `mxOrder` relevance hints for the MX market).
- Fix `.gitignore`: add `pubspec.lock` + `pubspec_overrides.yaml` (library
  packages should not track these) and remove a malformed line that had
  fused a comment with a pattern.

## 1.1.0 — 2026-04-16
- Add skills locale folders: `skills/es/` and `skills/en/` with 348 skills each
- Add 108 asset declarations in pubspec.yaml for locale-specific skill folders

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
