# Neomage

![Neomage — Flutter Agentic Sorcerer](https://firebasestorage.googleapis.com/v0/b/cyberneom-edd2d.appspot.com/o/AppStatics%2FNeomage%2FNeomage%20-%20Flutter%20Agentic%20Sorcerer.png?alt=media&token=5d50707f-4e71-4e6c-98ee-7aae6abd4df5)

[![pub package](https://img.shields.io/pub/v/neomage.svg)](https://pub.dev/packages/neomage)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Multi-provider AI agent engine for Flutter. API clients for Gemini, OpenAI, Anthropic, DeepSeek, Qwen, and Ollama with tool execution, skills, and MCP.

Part of the [Open Neom](https://github.com/Open-Neom) ecosystem.

## Features

- **Multi-provider** — Gemini, OpenAI, Anthropic, DeepSeek, Qwen, Ollama. One interface, any backend.
- **Agentic tool system** — 31 built-in tools (Bash, FileRead/Write/Edit, Grep, Glob, WebSearch, Agent, etc.) with automatic multi-turn execution loop.
- **Streaming** — Real-time SSE parsing with typed stream events (`TextDelta`, `ToolUseStart`, `ThinkingDelta`, etc.).
- **Skills framework** — 283 loadable markdown skills across 40+ categories (architecture, testing, debugging, agents, security, etc.).
- **Personality system** — 12 modular personality modules (Identity, Cognition, Tools, Agency, Memory, etc.) assembled into a dynamic system prompt with environment context.
- **MCP client** — Model Context Protocol support for extending capabilities with external tool servers.
- **Bash security** — Command validation with 20+ security checks (injection detection, IFS validation, obfuscated flags, etc.).
- **Context compaction** — Automatic conversation summarization to stay within token limits.
- **Retry with backoff** — Configurable exponential backoff with 529/rate-limit awareness.
- **Cross-platform** — macOS, Linux, Windows, Web, iOS, Android.

## Installation

```yaml
dependencies:
  neomage: ^1.0.0
```

```dart
import 'package:neomage/neomage.dart';
```

## Quick Start

### 1. Configure a provider

```dart
import 'package:neomage/neomage.dart';

// Use any OpenAI-compatible provider
final provider = ApiProvider(
  apiKey: 'your-api-key',
  baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
  model: 'gemini-2.5-flash',
);
```

### 2. Send messages

```dart
final message = Message.user('Explain the builder pattern in Dart');
final response = await provider.complete(messages: [message]);
print(response.textContent);
```

### 3. Stream responses

```dart
final stream = provider.stream(messages: [message]);
await for (final event in stream) {
  if (event is TextDelta) {
    stdout.write(event.text);
  }
}
```

### 4. Use the tool system

```dart
// Define tools
final tools = [
  ToolDefinition(
    name: 'read_file',
    description: 'Read contents of a file',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'File path to read'},
      },
      'required': ['path'],
    },
  ),
];

// The query engine handles the agentic loop automatically
final engine = QueryEngine(provider: provider, tools: tools);
final result = await engine.query(
  messages: [Message.user('Read the pubspec.yaml file')],
);
```

### 5. Validate bash commands

```dart
final result = bashCommandIsSafe('ls -la');
// result.isPassthrough → safe

final risky = bashCommandIsSafe('rm -rf / --no-preserve-root');
// risky.isAsk → needs user confirmation
```

### 6. Build system prompts with personality

```dart
// Load personality modules (call once at startup)
await NeomageSystemPrompt.load();

// Build a context-aware system prompt
final systemPrompt = NeomageSystemPrompt.build(
  model: 'gemini-2.5-flash',
  workingDirectory: '/home/user/project',
  gitBranch: 'feature/auth',
  projectLanguage: 'dart',
  projectFramework: 'flutter',
  loadedSkills: [codingSkill, testingSkill],
);
```

## Supported Providers

| Provider | Default Model | Endpoint |
|----------|--------------|----------|
| **Gemini** | gemini-2.5-flash | generativelanguage.googleapis.com |
| **OpenAI** | gpt-4o | api.openai.com |
| **Anthropic** | claude-sonnet-4 | api.anthropic.com |
| **DeepSeek** | deepseek-chat | api.deepseek.com |
| **Qwen** | qwen-plus | dashscope.aliyuncs.com |
| **Ollama** | llama3.1 | localhost:11434 (local) |

## Architecture

```
lib/
├── core/
│   ├── agent/          # System prompt builder, personality loader
│   └── platform/       # Cross-platform abstraction (dart:io stubs for web)
├── data/
│   ├── api/            # ApiProvider, AnthropicClient, OpenAiShim, SSE streaming
│   ├── auth/           # API key + provider config (secure storage)
│   ├── engine/         # QueryEngine — agentic conversation loop
│   ├── tools/          # 31 tools: Bash, FileRead/Write/Edit, Grep, Glob, Agent...
│   ├── compact/        # Context compaction (summarization strategies)
│   ├── services/       # Ollama, MCP, analytics, voice, git, sessions
│   └── commands/       # 24+ slash commands
├── domain/models/      # Message, ContentBlock, ToolDefinition, Permissions, IDs
├── state/              # Sint controllers and reactive state
└── utils/              # 25+ utility modules (config, telemetry, git, etc.)
```

## Example App

The `example/` directory contains a full AI coding assistant app built with neomage — demonstrates multi-provider chat, tool execution, skills system, MCP integration, and more.

```bash
cd example
flutter pub get
flutter run -d macos   # or: -d chrome, -d linux, -d windows
```

Features: streaming chat, Ollama local models, settings, onboarding, command palette, vim mode, dark/light theme, session browser, MCP panel.

## Testing

```bash
flutter test
```

The test suite covers domain models, API error classification, bash security validation, SSE parsing, retry logic, tool definitions, and system prompt assembly.

## Acknowledgements

Neomage's tool system architecture, system prompt design, and agentic loop patterns are inspired by [OpenClaw](https://github.com/anthropics/claude-code) (Claude Code by Anthropic). The tool descriptions, permission model, and query engine design follow patterns established by the OpenClaw/OpenClaude codebase. We are grateful to the Anthropic team for open-sourcing Claude Code, which served as the reference architecture for building a multi-provider agentic engine in Flutter.

## License

Apache License — see [LICENSE](LICENSE).

Built by the [Open Neom](https://github.com/Open-Neom) community.
