# Neom Claw — Migration Progress

## Source: OpenClaude TypeScript (~385K LOC, 1,367 files)
## Target: neom_claw (Flutter + Sint framework, Open Neom ecosystem)

---

## Current Stats: 291 files, ~185K LOC
## Migration: 36/36 directories ported

---

## Fase 1 — Core Foundation + Sint ✅

### ✅ Scaffold & Architecture
- [x] Rename to neom_claw, update pubspec.yaml
- [x] Replace Provider with Sint framework
- [x] Create ChatController (SintController + .obs)
- [x] Create RootBinding (Binding + List<Bind>)
- [x] Create ClawRoutes (SintPage + ClawRouteConstants)
- [x] Rewrite main.dart → SintMaterialApp + binds + sintPages
- [x] Refactor ChatScreen → Sint.find + Obx
- [x] Refactor SettingsScreen → Sint.find + Sint.back()
- [x] Refactor OnboardingScreen → Sint.find + Sint.offAllNamed()
- [x] Create SplashScreen (auth check + redirect)
- [x] Delete old chat_provider.dart
- [x] Restructure lib/ → domain/data/ui/utils
- [x] Create neom_claw.dart library export
- [x] dart analyze → 0 errors

### ✅ Domain Models (from types/)
- [x] ids.dart — SessionId, AgentId (extension types)
- [x] message.dart — Message, ContentBlock (sealed), TokenUsage
- [x] tool_definition.dart — ToolDefinition
- [x] permissions.dart — PermissionMode, PermissionRule, PermissionDecision
- [x] hooks.dart — HookCallback, HookResult, AggregatedHookResult
- [x] logs.dart — SerializedMessage, LogOption, FileAttributionState
- [x] command.dart — Command, PromptCommand, LocalCommandResult
- [x] plugin.dart — PluginManifest, PluginError, LoadedPlugin
- [x] entrypoints.dart — HookEvent, ExitReason, SandboxSettings, OutputStyleConfig
- [x] hook_schemas.dart — BashCommandHook, PromptHook, HttpHook, AgentHook
- [x] text_input_types.dart — VimMode, QueuedCommand, PromptInputMode, VimInputState

### ✅ Constants (from constants/)
- [x] api_limits.dart — Image/PDF/media size limits
- [x] betas.dart — API beta headers (20+ headers)
- [x] tool_limits.dart — Tool result size limits
- [x] tool_names.dart — All 30+ tool name constants + availability sets
- [x] xml_tags.dart — 30+ XML tag constants
- [x] figures.dart — Unicode figure constants
- [x] files.dart — Binary extension detection (110+ extensions)
- [x] messages.dart — Message constants
- [x] error_ids.dart — Error tracking IDs
- [x] oauth.dart — OAuth config constants
- [x] system.dart — System prompt prefixes
- [x] spinner_verbs.dart — 188 loading messages
- [x] neom_claw_assets.dart — Asset path constants (appIcon, logo)

### ✅ Data Layer — API (from services/api/)
- [x] api_provider.dart — Abstract ApiProvider, ApiConfig, StreamEvent
- [x] anthropic_client.dart — Anthropic Messages API + SSE streaming
- [x] openai_shim.dart — OpenAI-compatible API shim
- [x] gemini_client.dart — Native Gemini API with query-param auth
- [x] errors.dart — API error classification (20+ types)
- [x] retry.dart — Exponential backoff with jitter
- [x] streaming.dart — Full streaming support

### ✅ Data Layer — Auth
- [x] auth_service.dart — API key management (all providers)
- [x] oauth_service.dart — PKCE flow, token exchange/refresh

---

## Fase 2 — Tool System + Engine ✅

### ✅ Tools (from tools/)
- [x] tool.dart, tool_registry.dart — Base tool interface + registry
- [x] bash_tool.dart — Shell execution
- [x] bash_tool_full.dart — Extended bash with security
- [x] bash_security.dart — Command sanitization
- [x] file_read_tool.dart — File reading
- [x] file_write_tool.dart — File writing
- [x] file_edit_tool.dart — String replacement editing
- [x] grep_tool.dart — Content search
- [x] glob_tool.dart — File pattern matching
- [x] agent_tool.dart — Sub-agent launching
- [x] send_message_tool.dart — Agent messaging
- [x] todo_write_tool.dart — Todo tracking
- [x] web_fetch_tool.dart — HTTP fetching
- [x] web_search_tool.dart — Web search
- [x] lsp_tool.dart — Language Server Protocol
- [x] mcp_tool.dart — MCP tool bridge
- [x] notebook_edit_tool.dart — Jupyter notebook
- [x] plan_mode_tool.dart — Plan mode
- [x] powershell_tool.dart — PowerShell
- [x] config_tool.dart — Configuration
- [x] skill_tool.dart — Skill execution
- [x] tool_search_tool.dart — Tool discovery
- [x] task_output_tool.dart, task_update_tool.dart — Task management
- [x] tool_schemas.dart — Schema definitions
- [x] extended_tools.dart — Additional tools

### ✅ Engine (from query/, coordinator/)
- [x] query_engine.dart — Agentic loop with tool execution
- [x] conversation_engine.dart — Conversation management
- [x] system_prompt.dart — System prompt builder

### ✅ Compact (from services/compact/)
- [x] compaction_service.dart — Full compaction (strategies, token counting, 817 LOC)
- [x] compact_service.dart — Compact service with hooks

### ✅ Session (from assistant/, services/SessionMemory/)
- [x] session_history.dart — Session persistence
- [x] session_memory.dart — Session memory
- [x] session_restore.dart — Session restoration

### ✅ Memdir (from memdir/)
- [x] memdir_paths.dart — Memory directory paths
- [x] memdir_service.dart — NEOMCLAW.md, MEMORY.md management
- [x] memory_scan.dart — Memory scanning
- [x] memory_types.dart — Memory type definitions

---

## Fase 3 — Commands + Services ✅

### ✅ Commands (from commands/)
- [x] command.dart, command_registry.dart — Command framework
- [x] 24 builtin commands: branch, bridge, clear, commit, compact, context, cost,
      diff, help, insights, init_verifiers, mcp_add, memory, model, plan, review,
      security_review, session, terminal_setup, thinkback, ultraplan, xaa_idp,
      extended_commands

### ✅ Services (from services/)
- [x] analytics_service.dart — Analytics/telemetry
- [x] auto_dream_service.dart — Background AI tasks
- [x] autocomplete_service.dart — Autocomplete
- [x] clipboard_service.dart — Clipboard
- [x] compact_service.dart — Context compaction
- [x] config_service.dart — Configuration
- [x] conversation_service.dart — Conversation management
- [x] coordinator_service.dart — Task coordination
- [x] diff_service.dart — Diff generation
- [x] git_service.dart — Git integration
- [x] history_service.dart — History tracking
- [x] lsp_service.dart — Language Server Protocol
- [x] memory_extraction_service.dart — Memory extraction
- [x] notification_service_full.dart — Notifications
- [x] oauth_service.dart — OAuth flows
- [x] ollama_service.dart — Local Ollama integration
- [x] plugin_service.dart — Plugin management
- [x] project_service.dart — Project analysis
- [x] prompt_suggestion_service.dart — Prompt suggestions
- [x] rate_limit_service.dart — Rate limiting
- [x] remote_settings_service.dart — Remote settings
- [x] search_service.dart — Code search
- [x] session_memory_service.dart — Session memory
- [x] settings_sync_service.dart — Settings sync
- [x] task_service.dart — Task management
- [x] team_memory_service.dart — Team memory
- [x] tips_service.dart — Tips/suggestions
- [x] tool_execution_service.dart — Tool execution
- [x] voice_service.dart — Voice features

---

## Fase 4 — MCP + Skills + Hooks + UI ✅

### ✅ MCP (from services/mcp/)
- [x] mcp_client.dart — MCP client
- [x] mcp_config.dart — MCP configuration
- [x] mcp_transport.dart — MCP transport layer
- [x] mcp_types.dart — MCP type definitions

### ✅ Skills (from skills/)
- [x] skill.dart — Skill definition
- [x] skill_registry.dart — Skill registry

### ✅ Hooks (from hooks/)
- [x] hook_executor.dart — Hook execution engine
- [x] hook_manager.dart — Hook lifecycle management
- [x] hook_types.dart — Hook type definitions
- [x] lifecycle_hooks.dart — Lifecycle hooks
- [x] permission_hooks.dart — Permission hook system

### ✅ Plugins (from services/plugins/, utils/plugins/)
- [x] plugin_loader.dart — Plugin loading/discovery
- [x] plugin_service.dart — Plugin operations, install/uninstall, CLI

### ✅ UI Widgets (from components/)
- [x] 30 widgets: agent_panel, background_tasks_panel, command_palette,
      custom_select, design_system, diff_view, feedback_survey, input_bar,
      log_panel, markdown_preview, mcp_tool_views, memory_panel,
      message_bubble, message_renderer, permission_dialog, permission_manager,
      plan_mode_view, prompt_input, sandbox_settings, status_bar,
      status_notice, streaming_text, syntax_highlight, task_detail_views,
      teams_dialog, teleport_view, terminal_view, tool_output_widget,
      trust_dialog

### ✅ UI Screens (from screens/)
- [x] chat_screen.dart — Main chat interface
- [x] doctor_screen.dart — System diagnostics
- [x] mcp_panel_screen.dart — MCP management
- [x] ollama_setup_screen.dart — Local Ollama setup
- [x] onboarding_screen.dart — Multi-step onboarding wizard
- [x] session_browser_screen.dart — Session browser
- [x] settings_screen.dart — Settings
- [x] splash_screen.dart — Splash with auth check

### ✅ Keybindings + Vim (from keybindings/, vim/)
- [x] default_bindings.dart — Default keybindings
- [x] keybinding_resolver.dart — Keybinding resolution
- [x] keybinding_types.dart — Keybinding types
- [x] vim_mode.dart — Full Vim emulation

### ✅ Theme + Styles
- [x] app_theme.dart — Material Design theme
- [x] claw_theme_full.dart — Extended theme with ARGB colors
- [x] output_styles.dart — Output formatting styles

---

## Fase 5 — Bridge + Remote + Platform ✅

### ✅ Bridge (from bridge/)
- [x] bridge_protocol.dart — Bridge protocol
- [x] ide_bridge.dart — IDE integration
- [x] jetbrains_bridge.dart — JetBrains IDE
- [x] vscode_bridge.dart — VS Code integration

### ✅ Remote (from remote/)
- [x] remote_session_manager.dart — Remote session HTTP management
- [x] sessions_websocket.dart — WebSocket with reconnection
- [x] remote_permission_bridge.dart — Synthetic permission stubs
- [x] sdk_message_adapter.dart — SDK message conversion

### ✅ Server + Proxy
- [x] direct_server.dart — Direct server
- [x] upstream_proxy.dart — Upstream proxy

### ✅ Voice (from voice/)
- [x] voice_service.dart — Voice mode, language normalization

### ✅ Platform (from platform/)
- [x] cli_adapter.dart — CLI adapter
- [x] file_watcher.dart — File watching
- [x] native_bridge.dart — Native bridge
- [x] notification_service.dart — Notifications
- [x] platform_bridge.dart — Platform abstraction
- [x] remote_bridge.dart — Remote bridge
- [x] remote_session.dart — Remote session

### ✅ Core Platform
- [x] claw_io.dart — IO abstraction (web + native)
- [x] platform_init.dart — Platform initialization
- [x] native_platform.dart / web_platform.dart — Platform implementations

---

## Fase 6 — Utils ✅

### ✅ Utils (82 files, ~65K LOC)
- [x] analyze/, attachments/, auth/, bash/, billing/, cleanup/, collapse/,
      commit/, computer_use/, config/, constants/, context/, conversation/,
      cron/, crypto/, deep_link/, diff/, doctor/, effort/, env/, error/,
      fast_mode/, file/, file_history/, format/, fs/, git/, handle_prompt/,
      heatmap/, hooks/, ide/, image/, input/, markdown/, message_queue/,
      messages/, migration/, model/, native_installer/, neomclawmd/, path/,
      permissions/, plugins/, process/, provider/, proxy/, query/,
      release/, ripgrep/, session/, settings/, shell/, stats/, swarm/,
      teammate/, telemetry/, text/, theme/, tokens/, tool_result/,
      tool_search/, worktree/

---

## Infrastructure ✅

- [x] sint_sentinel integration (circuit breaker + Logger)
- [x] SintSentinel.logger replaces all print() calls
- [x] Hive persistence for sentinel state
- [x] macOS entitlements (network.client + keychain)
- [x] flutter_launcher_icons for all platforms
- [x] NeomClawAssets constants
- [x] 160/160 pub.dev score (achieved prior to migration completion)
- [x] Provider-agnostic — no Itzli/model-specific references
- [x] macOS build verified ✓

---

## Remaining / Nice-to-Have

- [ ] Integration: OAuth login flow in OnboardingScreen
- [ ] Test: manual chat with ≥3 providers end-to-end
- [ ] iOS build (requires iOS SDK 26.4 in Xcode)
- [ ] Android build verification
- [ ] Web build verification
- [ ] Unit tests for core services
- [ ] Integration tests for onboarding flow
- [ ] Publish to pub.dev (after testing)

---

## File Structure

```
lib/ (291 files, ~185K LOC)
├── main.dart
├── claw_routes.dart
├── root_binding.dart
├── neom_claw.dart              (library export)
├── core/platform/              (9 files, ~2.5K LOC)
├── data/                       (137 files, ~75K LOC)
│   ├── api/                    (anthropic, gemini, openai_shim, errors, retry, streaming)
│   ├── auth/                   (auth_service, oauth_service)
│   ├── bootstrap/              (app_state, bootstrap_service)
│   ├── bridge/                 (ide, vscode, jetbrains, protocol)
│   ├── commands/builtin/       (24 commands)
│   ├── compact/                (compaction_service)
│   ├── engine/                 (query_engine, conversation_engine, system_prompt)
│   ├── hooks/                  (executor, manager, types, lifecycle, permissions)
│   ├── mcp/                    (client, config, transport, types)
│   ├── memdir/                 (paths, service, scan, types)
│   ├── platform/               (cli, watcher, bridges, notifications)
│   ├── plugins/                (loader, service)
│   ├── proxy/                  (upstream_proxy)
│   ├── remote/                 (session_manager, websocket, permission_bridge, adapter)
│   ├── server/                 (direct_server)
│   ├── services/               (32 services)
│   ├── session/                (history, memory, restore)
│   ├── skills/                 (skill, registry)
│   ├── tools/                  (31 tools)
│   └── voice/                  (voice_service)
├── domain/models/              (12 files, ~3.2K LOC)
├── state/                      (1 file, ~766 LOC)
├── ui/                         (46 files, ~37K LOC)
│   ├── buddy/                  (buddy_widget)
│   ├── controllers/            (chat_controller)
│   ├── keybindings/            (bindings, resolver, types)
│   ├── screens/                (8 screens)
│   ├── styles/                 (output_styles)
│   ├── theme/                  (app_theme, claw_theme_full)
│   ├── vim/                    (vim_mode)
│   └── widgets/                (30 widgets)
└── utils/                      (82 files, ~65K LOC)
```

---

## Key Decisions
- Sint framework (not Provider/Riverpod) — matches Open Neom ecosystem
- Extension types for branded IDs (SessionId, AgentId) — zero-cost Dart equivalent
- Sealed classes for unions (ContentBlock, PermissionDecision, etc.)
- SintSentinel for circuit breaker + centralized Logger
- Native GeminiClient (not OpenAI shim) — Gemini uses different auth/endpoints
- Provider-agnostic: works with Gemini, OpenAI, Anthropic, DeepSeek, Qwen, Ollama
- API keys stored in flutter_secure_storage (Keychain on macOS)
