# NeomClaw (flutter_claw)

AI coding assistant built with Flutter — any model, any platform.

Part of the [Open Neom](https://github.com/Open-Neom) ecosystem.

## Features

- **Multi-provider**: Gemini, Qwen, OpenAI, DeepSeek, Anthropic, Ollama — just API key + model + endpoint
- **Local models**: Built-in Ollama manager — download, test, and run models locally with no API key
- **Agentic tools**: Bash, file read/write/edit, grep, glob — automatic multi-turn execution
- **Multimodal**: Image and file attachments, PDF support
- **Streaming**: Real-time token streaming with live UI
- **MCP Client**: Model Context Protocol support for extending capabilities
- **Cross-platform**: macOS, Linux, Windows, Web, iOS, Android
- **Dark/light theme**: Material 3

## Quick Start

```bash
git clone https://github.com/Open-Neom/flutter_claw.git
cd flutter_claw

flutter pub get

# Desktop (recommended — full tool support)
flutter run -d macos
flutter run -d linux
flutter run -d windows

# Web (chat + settings, tools via backend server)
flutter run -d chrome

# Mobile (chat only)
flutter run -d ios
flutter run -d android
```

## Local Models (Ollama)

Run AI models locally — free, private, no API key needed:

1. Install [Ollama](https://ollama.com/download)
2. Open NeomClaw → Settings → Local Models (Ollama)
3. Download a model (e.g. `qwen2.5-coder:7b`)
4. Click "Use This Model" → done

Recommended coding models:
- `qwen2.5-coder:7b` — best small coding model (4.7 GB)
- `deepseek-coder-v2:16b` — DeepSeek Coder v2 (8.9 GB)
- `llama3.1:8b` — general purpose (4.7 GB)

## Provider Setup

On first launch, select your provider and enter your API key:

| Provider | Default Model | API Key |
|----------|--------------|---------|
| **Gemini** | gemini-2.5-flash | [Google AI Studio](https://aistudio.google.com/apikey) |
| **Qwen** | qwen-plus | [DashScope](https://dashscope.console.aliyun.com/) |
| **OpenAI** | gpt-4o | [platform.openai.com](https://platform.openai.com) |
| **DeepSeek** | deepseek-chat | [platform.deepseek.com](https://platform.deepseek.com) |
| **Anthropic** | claude-sonnet-4 | [console.anthropic.com](https://console.anthropic.com) |
| **Ollama** | llama3.1 | Not needed (local) |

## Architecture

```
lib/
├── core/platform/         # Cross-platform abstraction (dart:io stubs for web)
├── data/
│   ├── api/               # ApiProvider, AnthropicClient, OpenAiShim
│   ├── auth/              # API key + provider config (secure storage)
│   ├── engine/            # QueryEngine — agentic conversation loop
│   ├── services/          # Ollama, MCP, analytics, voice, git, etc.
│   └── tools/             # Bash, FileRead/Write/Edit, Grep, Glob, WebSearch
├── domain/models/         # Message, ContentBlock, ToolDefinition, Permissions
├── ui/
│   ├── screens/           # Chat, Settings, Onboarding, Ollama Setup, MCP Panel
│   ├── controllers/       # ChatController (Sint)
│   └── widgets/           # InputBar, MessageBubble, PromptInput, DesignSystem
└── utils/                 # 25+ utility modules (config, telemetry, git, etc.)
```

**283 files / ~179K LOC Dart** — provider-agnostic, uses [Sint](https://pub.dev/packages/sint) framework.

## Platform Support

| Platform | Chat | Tools (Bash/File) | Local Models |
|----------|------|-------------------|--------------|
| macOS    | Yes  | Yes               | Yes (Ollama) |
| Linux    | Yes  | Yes               | Yes (Ollama) |
| Windows  | Yes  | Yes               | Yes (Ollama) |
| Web      | Yes  | Via backend       | No           |
| iOS      | Yes  | No                | No           |
| Android  | Yes  | No                | No           |

## License

MIT — see [LICENSE](LICENSE).

Built by the [Open Neom](https://github.com/Open-Neom) community.
