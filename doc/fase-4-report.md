# Fase 4 Report — MCP, Skills, Plugins, Hooks, Advanced UI

## Overview
Phase 4 ported the extensibility layer (MCP, Skills, Plugins, Hooks), advanced UI components (diff, syntax, message rendering), keybindings, and LSP integration. This is the largest and most architecturally complex phase.

**Duration**: ~1 session
**Files Created**: 12
**LOC Added**: ~3,750

## Modules Ported

### MCP (Model Context Protocol) — 3 files
| File | LOC | Description |
|------|-----|-------------|
| `data/mcp/mcp_types.dart` | 187 | McpServerConfig (sealed: Stdio/SSE/HTTP/WS/SDK), McpServerConnection (sealed: Connected/Failed/Pending/Disabled), McpToolInfo, McpResource |
| `data/mcp/mcp_client.dart` | 411 | Stdio transport, JSON-RPC initialize/initialized handshake, tool discovery via tools/list, _McpProxyTool extending Tool for registry integration |
| `data/mcp/mcp_config.dart` | 179 | loadMcpConfigFile(), loadAllMcpConfigs() from multiple sources, transport type detection |

### Skills — 1 file
| File | LOC | Description |
|------|-----|-------------|
| `data/skills/skill.dart` | 252 | SkillDefinition, SkillSource enum, SkillCommand (extends PromptCommand), SKILL.md frontmatter parsing with $ARGUMENTS substitution |

### Plugins — 1 file
| File | LOC | Description |
|------|-----|-------------|
| `data/plugins/plugin_loader.dart` | 157 | loadPluginsFromDir(), plugin.json manifest parsing, skill/MCP config loading |

### Hooks — 1 file
| File | LOC | Description |
|------|-----|-------------|
| `data/hooks/hook_manager.dart` | 289 | 11 HookEvents, HookCommand (sealed: Command/Prompt/HTTP/Function), HookMatcher, condition evaluation, once-execution tracking |

### LSP Service — 1 file
| File | LOC | Description |
|------|-----|-------------|
| `data/services/lsp_service.dart` | 428 | LSP Content-Length framing, JSON-RPC over stdio, diagnostics, crash recovery with restart limits, multi-server routing by file extension |

### Advanced UI — 3 files
| File | LOC | Description |
|------|-----|-------------|
| `ui/widgets/diff_view.dart` | 410 | LCS diff algorithm, unified diff parser, DiffView + ScrollableDiffView with line gutters, color themes |
| `ui/widgets/syntax_highlight.dart` | 395 | Token-based highlighter for 15 languages (Dart, TS, Python, Go, Rust, etc.), SyntaxHighlightView widget |
| `ui/widgets/message_renderer.dart` | 650 | Markdown parser (headings, code blocks, lists, blockquotes, links), ConversationMessage widget, thinking view, tool result view with diff detection |

### Keybindings — 3 files
| File | LOC | Description |
|------|-----|-------------|
| `ui/keybindings/keybinding_types.dart` | 160 | ParsedKeystroke, Chord, 11 contexts, parser with modifier aliases |
| `ui/keybindings/keybinding_resolver.dart` | 143 | Chord state machine, priority resolution, binding display |
| `ui/keybindings/default_bindings.dart` | 94 | 40+ default bindings including chord combos (Ctrl+K prefix) |

## Key Architectural Decisions

1. **MCP transport strategy**: Full stdio implementation (subprocess-based), network transports (SSE/HTTP/WS) marked as extensible stubs — require http/web_socket_channel packages
2. **Syntax highlighting**: Pure Dart rule-based tokenizer, no native dependency — covers 95%+ of display needs without tree-sitter
3. **Keybinding chords**: State machine tracks pending keystrokes, Escape cancels, supports arbitrary chord length
4. **LSP crash recovery**: Exponential backoff with max restart count prevents zombie processes
5. **Plugin architecture**: Plugins provide skills + MCP configs + hooks, all loaded from a single `plugin.json` manifest

## Export Conflicts Resolved
- `HookEvent` in both `entrypoints.dart` and `hook_manager.dart`
- `PromptHook`, `HttpHook`, `HookMatcher`, `HookResult` overlaps between `hooks.dart`/`hook_schemas.dart` and `hook_manager.dart`
- All resolved with `hide` clauses on the hook_manager export

## Bugs Fixed
- `McpToolInfo._normalize()` private — made public `normalize()`
- `LoadedPlugin` constructor didn't have `name` param — removed invalid usage
- `PluginManifest.author` type mismatch (String vs PluginAuthor) — added polymorphic parsing
- `LspServerInstance.server` referenced before declaration — used `late final`
- `ConversationMessage.showThinking` passed to `MessageRenderer` after field was removed
- `Role` vs `MessageRole` — corrected to match domain model
