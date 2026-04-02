# OpenClaude Flutter

Flutter implementation of Claude Code — a multi-platform AI coding assistant.

Part of the [Open Neom](https://github.com/Open-Neom) ecosystem.

---

## Features

- **Multi-provider support**: Anthropic Claude, OpenAI, Ollama, DeepSeek, Mistral, and any OpenAI-compatible API
- **Multi-platform**: iOS, Android, macOS, Linux, Windows, Web
- **Streaming responses**: Real-time token streaming with live UI updates
- **Tool use (agentic loop)**: Bash, file read/write/edit, grep, glob — with automatic multi-turn tool execution
- **OpenAI shim**: Translates Anthropic message format to OpenAI chat completions, so the entire codebase works with any provider
- **Secure storage**: API keys stored in platform-native secure storage (Keychain, Keystore, etc.)
- **Dark/light theme**: Material 3 with JetBrains Mono typography

## Architecture

```
lib/
├── main.dart                      # App entry point
├── core/
│   ├── api/
│   │   ├── api_provider.dart      # Abstract provider + stream events
│   │   ├── anthropic_client.dart  # Native Anthropic Messages API
│   │   └── openai_shim.dart       # OpenAI-compatible translation layer
│   ├── engine/
│   │   └── query_engine.dart      # Agentic conversation loop
│   ├── tools/
│   │   ├── tool.dart              # Abstract tool base
│   │   ├── tool_registry.dart     # Tool registration & dispatch
│   │   ├── bash_tool.dart         # Shell command execution
│   │   ├── file_read_tool.dart    # Read files with line numbers
│   │   ├── file_write_tool.dart   # Write/create files
│   │   ├── file_edit_tool.dart    # String replacement editing
│   │   ├── grep_tool.dart         # Regex content search
│   │   └── glob_tool.dart         # File pattern matching
│   ├── auth/
│   │   └── auth_service.dart      # API key + provider config
│   ├── config/
│   │   └── settings.dart          # App settings
│   └── models/
│       ├── message.dart           # Message, ContentBlock, TokenUsage
│       └── tool_definition.dart   # Tool schema for API
├── ui/
│   ├── screens/
│   │   ├── chat_screen.dart       # Main chat interface
│   │   ├── settings_screen.dart   # Provider & model configuration
│   │   └── onboarding_screen.dart # First-run API key setup
│   ├── widgets/
│   │   ├── message_bubble.dart    # Message display with markdown
│   │   ├── input_bar.dart         # Text input with send button
│   │   └── streaming_text.dart    # Live streaming display
│   └── theme/
│       └── app_theme.dart         # Material 3 theme
└── state/
    └── chat_provider.dart         # Main app state (ChangeNotifier)
```

## Platform Support

| Platform | Chat | Tools (Bash/File) | Status |
|----------|------|-------------------|--------|
| macOS    | Yes  | Yes               | Full   |
| Linux    | Yes  | Yes               | Full   |
| Windows  | Yes  | Yes (PowerShell)  | Full   |
| Web      | Yes  | No                | Chat only |
| iOS      | Yes  | No                | Chat only |
| Android  | Yes  | No                | Chat only |

## Quick Start

```bash
# Clone
git clone https://github.com/Open-Neom/openclaude_flutter.git
cd openclaude_flutter

# Install dependencies
flutter pub get

# Run (macOS)
flutter run -d macos

# Run (web)
flutter run -d chrome

# Run (iOS simulator)
flutter run -d ios
```

## Configuration

On first launch, select your provider and enter your API key:

- **Anthropic**: Get a key at console.anthropic.com
- **OpenAI**: Get a key at platform.openai.com
- **Ollama**: Run locally — no key needed (`ollama serve`)

## How It Works

The architecture mirrors OpenClaude (the TypeScript original), reimplemented in Dart/Flutter:

1. **ApiProvider** — abstract interface for message streaming
2. **AnthropicClient** — native Anthropic Messages API with SSE parsing
3. **OpenAiShim** — translates Anthropic format to OpenAI format, so the engine is provider-agnostic
4. **QueryEngine** — implements the agentic loop: send message -> receive response -> extract tool calls -> execute tools -> inject results -> repeat
5. **ToolRegistry** — registers platform-appropriate tools and dispatches execution
6. **ChatProvider** — Flutter state management binding everything together

## Origin

This is a **clean-room Flutter reimplementation** inspired by the architecture of OpenClaude. No TypeScript source code was copied — all Dart code was written from scratch following the same architectural patterns.

This project is **not affiliated with or endorsed by Anthropic**.

## License

MIT

---

Built for the [Open Neom](https://github.com/Open-Neom) community.
