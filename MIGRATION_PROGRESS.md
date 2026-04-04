# Neom Claw — Migration Progress

## Source: NeomClaw TypeScript reference (~517K LOC, 1,921 files)
## Target: neom_claw (Flutter + Sint framework, Open Neom ecosystem)

---

## Current Phase: FASE 1 — Core Foundation + Sint
**Goal:** Chat with any LLM using API key + model + endpoint.
**Target LOC:** ~8,000 Dart

### Status: IN PROGRESS (~5,540 LOC, 52 files)

---

## Fase 1 Checklist

### ✅ Scaffold & Architecture
- [x] Rename to flutter_claw, update pubspec.yaml
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
- [x] Create flutter_claw.dart library export
- [x] dart analyze → 0 errors

### ✅ Domain Models (from types/)
- [x] ids.dart — SessionId, AgentId (extension types)
- [x] message.dart — Message, ContentBlock (sealed), TokenUsage (pre-existing)
- [x] tool_definition.dart — ToolDefinition (pre-existing)
- [x] permissions.dart — PermissionMode, PermissionRule, PermissionDecision, etc.
- [x] hooks.dart — HookCallback, HookResult, AggregatedHookResult, etc.
- [x] logs.dart — SerializedMessage, LogOption, FileAttributionState, etc.
- [x] command.dart — Command, PromptCommand, LocalCommandResult, etc.
- [x] plugin.dart — PluginManifest, PluginError, LoadedPlugin
- [x] entrypoints.dart — HookEvent, ExitReason, SandboxSettings, OutputStyleConfig
- [x] hook_schemas.dart — BashCommandHook, PromptHook, HttpHook, AgentHook
- [ ] text_input_types.dart — VimMode, QueuedCommand, PromptInputMode

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
- [x] oauth.dart — OAuth config constants (endpoints, scopes, client IDs)
- [x] system.dart — System prompt prefixes
- [ ] spinner_verbs.dart — 200+ loading messages (nice-to-have)

### ✅ Data Layer (from services/)
- [x] api_provider.dart — Abstract ApiProvider, ApiConfig, StreamEvent (pre-existing)
- [x] anthropic_client.dart — Anthropic Messages API + SSE streaming (pre-existing)
- [x] openai_shim.dart — OpenAI-compatible API shim (pre-existing)
- [x] errors.dart — API error classification (20+ types)
- [x] retry.dart — Exponential backoff with jitter, configurable retry
- [x] auth_service.dart — API key management (pre-existing)
- [x] oauth_service.dart — PKCE flow, token exchange/refresh
- [x] query_engine.dart — Agentic loop (pre-existing)
- [x] app_state.dart — Bootstrap state (session, metrics, config)

### ✅ Tools (pre-existing from initial scaffold)
- [x] tool.dart, tool_registry.dart — Base tool interface + registry
- [x] bash_tool.dart, file_read_tool.dart, file_write_tool.dart
- [x] file_edit_tool.dart, grep_tool.dart, glob_tool.dart

### ⬜ Remaining Fase 1 Items
- [x] Port entrypoints/ → domain/models/entrypoints.dart (SDK types, sandbox, output styles)
- [x] Port schemas/ → domain/models/hook_schemas.dart (hook config schemas)
- [ ] Port context/ → adapt to Sint controllers (state/context/) — Fase 2+
- [x] Port moreright/ — SKIPPED (internal Anthropic stub, not useful for OSS)
- [x] Port outputStyles/ → domain/models/entrypoints.dart (OutputStyleConfig)
- [x] Integration: wire retry logic into AnthropicClient
- [x] Integration: wire errors into QueryEngine error handling
- [ ] Integration: add OAuth login flow to OnboardingScreen
- [ ] Verify: flutter build macos && flutter build web
- [ ] Test: manual chat with ≥2 providers

---

## Fase 2 — Tool System + Query Engine (Weeks 5-9) ⬜
**Target:** ~23,000 LOC cumulative

- [ ] Port Tool.ts → enhanced tools/tool.dart with permissions
- [ ] Port QueryEngine.ts enhancements → agentic loop improvements
- [ ] Port tools/ P1 (8 core tools) — enhance existing implementations
- [ ] Port tools/ P2 (6 agent tools) — AgentTool, SendMessage, TodoWrite, etc.
- [ ] Port services/tools/ → tool execution service
- [ ] Port services/compact/ → context compaction
- [ ] Port assistant/ → session history
- [ ] Port memdir/ → persistent memory (NEOMCLAW.md, MEMORY.md)
- [ ] Port services/SessionMemory/
- [ ] Port migrations/
- [ ] Permission system UI (Flutter dialogs)
- [ ] Verify: "Read file X, fix bug, commit" works end-to-end

## Fase 3 — Commands + Analytics + Sessions (Weeks 10-14) ⬜
**Target:** ~41,000 LOC cumulative

- [ ] Port commands/ (75+ slash commands)
- [ ] Port services/analytics/ (GrowthBook, Datadog, events)
- [ ] Port services/tips/, services/PromptSuggestion/
- [ ] Port services/policyLimits/, services/remoteManagedSettings/
- [ ] Port services/extractMemories/, services/teamMemorySync/
- [ ] Port coordinator/, tasks/, buddy/
- [ ] Session persistence (sqflite)
- [ ] Command palette widget

## Fase 4 — MCP + Skills + Advanced Tools + UI (Weeks 15-19) ⬜
**Target:** ~56,000 LOC cumulative

- [ ] Port services/mcp/ — MCP client complete
- [ ] Port skills/
- [ ] Port remaining tools (P3)
- [ ] Port services/lsp/, services/plugins/
- [ ] Port keybindings/, vim/
- [ ] Port hooks/ → Sint workers
- [ ] Port components/ → Flutter widgets (diff viz, syntax highlight, etc.)

## Fase 5 — Bridge + Remote + Platform + Polish (Weeks 20-26) ⬜
**Target:** ~70,000 LOC cumulative

- [ ] Port bridge/, remote/, server/
- [ ] Port upstreamproxy/, native-ts/ (FFI)
- [ ] Port cli/ (extract logic), ink/ (extract logic)
- [ ] Port voice/, screens/ (Doctor, Resume)
- [ ] Port plugins/ system complete
- [ ] Port remaining utils/

---

## File Structure

```
lib/ (52 files, ~5,540 LOC)
├── main.dart
├── claw_routes.dart
├── root_binding.dart
├── flutter_claw.dart          (library export)
├── domain/
│   └── models/                (ids, message, permissions, hooks, hook_schemas, logs,
│                               command, plugin, entrypoints, tool_definition)
├── data/
│   ├── api/                   (anthropic_client, api_provider, openai_shim, errors, retry)
│   ├── auth/                  (auth_service, oauth_service)
│   ├── bootstrap/             (app_state)
│   ├── engine/                (query_engine)
│   └── tools/                 (tool, tool_registry, bash, file_read/write/edit, grep, glob)
├── ui/
│   ├── controllers/           (chat_controller)
│   ├── screens/               (chat, onboarding, settings, splash)
│   ├── theme/                 (app_theme)
│   └── widgets/               (input_bar, message_bubble, streaming_text)
└── utils/
    ├── config/                (settings)
    └── constants/             (api_limits, betas, error_ids, figures, files, messages,
                                oauth, system, tool_limits, tool_names, xml_tags)
```

---

## Key Decisions
- Sint framework (not Provider/Riverpod) — matches Open Neom ecosystem
- Extension types for branded IDs (SessionId, AgentId) — zero-cost Dart equivalent
- Sealed classes for unions (ContentBlock, PermissionDecision, LocalCommandResult, etc.)
- All analytics/telemetry ported for reverse engineering — pruned later
- API-agnostic: works with any OpenAI-compatible endpoint
