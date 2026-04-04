# Fase 1: Core Foundation + Sint — Reporte Completo

**Proyecto:** flutter_claw (Open Neom)
**Fuente:** NeomClaw (~517,610 LOC TypeScript, 1,921 archivos)
**Fecha de inicio:** Marzo 2026
**Fecha de cierre Fase 1:** Abril 2026
**Estado:** COMPLETADA

---

## Resumen Ejecutivo

La Fase 1 estableció los cimientos del proyecto: modelos de dominio, capa API provider-agnostic, sistema de autenticación OAuth PKCE, bootstrap de estado, framework Sint integrado, y UI funcional con chat, onboarding y settings. Se logró la meta de tener una app Flutter compilable que puede comunicarse con cualquier LLM via API key + modelo + endpoint.

---

## Métricas al cierre de Fase 1

| Métrica | Valor |
|---------|-------|
| Archivos Dart | ~52 |
| LOC Dart | ~5,500 |
| Directorios TS migrados | 11/36 |
| Issues `flutter analyze` | 2 (info-level) |
| Dependencias externas | 12 packages |

---

## Módulos Migrados

### 1. Domain Models (`lib/domain/models/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `message.dart` | 141 | `src/types/message.ts` | ContentBlock (sealed class), Message, TokenUsage, MessageRole, StopReason |
| `permissions.dart` | 221 | `src/types/permissions.ts` | PermissionMode, PermissionDecision (sealed), PermissionRule, RiskLevel, YoloClassifierResult, ToolPermissionContext |
| `hooks.dart` | ~60 | `src/types/hooks.ts` | HookEventType, PromptRequest, HookResult, AggregatedHookResult |
| `logs.dart` | 213 | `src/types/log.ts` | LogEntry (sealed), SerializedMessage, LogOption, SummaryMessage |
| `command.dart` | ~80 | `src/types/command.ts` | LocalCommandResult (sealed: Text/Compact/Skip), CommandBase, PromptCommand |
| `plugin.dart` | ~70 | `src/types/plugin.ts` | PluginManifest, LoadedPlugin, PluginError (sealed), PluginLoadResult |
| `entrypoints.dart` | ~90 | `src/entrypoints/` | 27 HookEvents, 6 ExitReasons, SandboxSettings, OutputStyleConfig |
| `hook_schemas.dart` | 141 | `src/types/hookSchemas.ts` | HookConfig, BashCommandHook, PromptHook, HttpHook, AgentHook, HooksSettings |
| `ids.dart` | ~30 | `src/types/ids.ts` | SessionId, AgentId (extension types — zero-cost wrappers) |
| `tool_definition.dart` | ~20 | `src/Tool.ts` | ToolDefinition (name, description, inputSchema) |

**Patrones clave aplicados:**
- TypeScript discriminated unions → Dart **sealed classes** (ContentBlock, PermissionDecision, LocalCommandResult, PluginError, LogEntry)
- TypeScript branded types → Dart **extension types** (SessionId, AgentId)
- TypeScript interfaces → Dart abstract classes con factories

### 2. API Layer (`lib/data/api/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `api_provider.dart` | 138 | `src/services/api/client.ts` | ApiProvider (abstract), ApiConfig (.anthropic/.openai/.ollama factories), StreamEvent (sealed: 7 tipos), ApiProviderType enum |
| `anthropic_client.dart` | 247 | `src/services/api/claude.ts` | AnthropicClient: SSE streaming, message parsing, retry wrapping, error classification |
| `openai_shim.dart` | 401 | `src/services/api/openaiShim.ts` | OpenAiShim: format translation Anthropic→OpenAI y viceversa, SSE streaming, tool call mapping |
| `errors.dart` | 252 | `src/services/api/errors.ts` | ApiErrorType (15 tipos), ApiError con isRetryable/isAuthError, classifyApiError(), getAssistantMessageFromError() |
| `retry.dart` | 176 | `src/services/api/withRetry.ts` | RetryConfig (default + background), exponential backoff + jitter, Retry-After header, withRetry() genérico |

**Decisión arquitectónica:** Provider-agnostic. Solo necesita API key + modelo + endpoint. Soporta Anthropic, OpenAI, Ollama, Bedrock, Vertex, y custom.

### 3. Authentication (`lib/data/auth/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `auth_service.dart` | ~60 | `src/services/oauth/` | AuthService: API key + OAuth token management, secure storage |
| `oauth_service.dart` | 217 | `src/services/oauth/` | OAuth PKCE completo: code verifier/challenge (SHA-256), token exchange, refresh con 5-min buffer, OAuthConfig presets (claudeAi, console) |

### 4. Bootstrap (`lib/data/bootstrap/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `app_state.dart` | ~120 | `src/bootstrap/state.ts` | AppState: session identity, cost/metrics tracking, timing, model config, feature flags, session management methods |

### 5. Constants (`lib/utils/constants/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `api_limits.dart` | ~40 | `src/constants/` | Image/PDF/media size limits |
| `betas.dart` | ~50 | `src/constants/` | 20+ API beta headers |
| `tool_limits.dart` | ~30 | `src/constants/` | Tool result size limits (50K chars, 100K tokens) |
| `tool_names.dart` | ~60 | `src/constants/` | 30+ tool name constants + 4 availability sets |
| `xml_tags.dart` | ~50 | `src/constants/` | 30+ XML tag constants |
| `figures.dart` | ~20 | `src/constants/` | Unicode figures (platform-dependent) |
| `files.dart` | ~80 | `src/constants/` | 110+ binary extensions, hasBinaryExtension(), isBinaryContent() |
| `messages.dart` | ~10 | `src/constants/` | noContentMessage |
| `error_ids.dart` | ~15 | `src/constants/` | Error tracking IDs |
| `oauth.dart` | ~20 | `src/constants/` | Client ID, endpoints, scopes |
| `system.dart` | ~25 | `src/constants/` | System prompt prefixes, product URLs |
| `spinner_verbs.dart` | ~60 | `src/constants/` | 188 loading verbs + getRandomSpinnerVerb() |

### 6. Tools Core (`lib/data/tools/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `tool.dart` | 229 | `src/Tool.ts` | Tool base class con 25+ methods/properties, ValidationResult, InterruptBehavior, ToolUseContext, AbortSignal, ShellToolMixin, ReadOnlyToolMixin, FileWriteToolMixin |
| `tool_registry.dart` | 47 | `src/services/tools/` | ToolRegistry: register/unregister/execute |
| `bash_tool.dart` | ~70 | `src/tools/BashTool/` | Process.run con timeout, ShellToolMixin |
| `file_read_tool.dart` | ~70 | `src/tools/FileReadTool/` | File read con line numbers, ReadOnlyToolMixin |
| `file_write_tool.dart` | ~56 | `src/tools/FileWriteTool/` | File write con parent dir creation, FileWriteToolMixin |
| `file_edit_tool.dart` | ~93 | `src/tools/FileEditTool/` | String replacement con uniqueness check, FileWriteToolMixin |
| `grep_tool.dart` | ~122 | `src/tools/GrepTool/` | RegExp search recursivo, ReadOnlyToolMixin |
| `glob_tool.dart` | ~104 | `src/tools/GlobTool/` | Pattern matching con extension extraction, ReadOnlyToolMixin |

### 7. Engine (`lib/data/engine/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `query_engine.dart` | ~175 | `src/QueryEngine.ts` | Agentic loop: message→API→tool extraction→execution→result injection, SSE stream parsing |

### 8. UI (`lib/ui/`)

| Archivo | LOC | Descripción |
|---------|-----|-------------|
| `controllers/chat_controller.dart` | 150 | SintController: messages.obs, isStreaming.obs, currentModel.obs |
| `screens/chat_screen.dart` | 209 | Chat view con Obx(), Sint.find, message list |
| `screens/onboarding_screen.dart` | 168 | API key + model + endpoint config |
| `screens/settings_screen.dart` | 224 | Provider config, model selection |
| `screens/splash_screen.dart` | ~40 | Auth check + redirect |
| `widgets/message_bubble.dart` | 156 | Message rendering con role styling |
| `widgets/streaming_text.dart` | 145 | Animated text streaming |
| `widgets/input_bar.dart` | ~80 | Chat input field |
| `theme/app_theme.dart` | ~60 | Light/dark Material 3 themes |

### 9. App Structure

| Archivo | LOC | Descripción |
|---------|-----|-------------|
| `main.dart` | ~30 | SintMaterialApp con binds, sintPages, initialRoute |
| `root_binding.dart` | ~15 | RootBinding con ChatController permanent |
| `claw_routes.dart` | ~30 | SintPage routes: /, /onboarding, /chat, /settings |
| `flutter_claw.dart` | ~55 | Library export file |
| `utils/config/settings.dart` | ~40 | Settings persistence |

---

## Decisiones Técnicas Clave

1. **Sint sobre Provider/Riverpod** — Consistencia con ecosistema Open Neom
2. **SintMaterialApp** — Usa `sintPages` (no `getPages`), `binds` (no `initialBinding`)
3. **Sealed classes** — Para todas las uniones discriminadas de TypeScript
4. **Extension types** — Para IDs tipados (SessionId, AgentId) con cero overhead
5. **Provider-agnostic** — Cualquier LLM con API key + modelo + endpoint
6. **OAuth PKCE** — Flujo completo con refresh automático y buffer de 5 minutos

---

## Problemas Resueltos

| Problema | Solución |
|----------|----------|
| SintMaterialApp params incorrectos | Exploración del source de Sint → `sintPages` y `binds` |
| No root `/` route | Creación de SplashScreen + route `/` |
| Dangling library doc comments | `///` → `//` en archivos no-library |
| Package name en test | Actualización a `flutter_claw` + `FlutterClawApp` |
| crypto package faltante | Agregado `crypto: ^3.0.0` a pubspec.yaml |
| flutter no en PATH | Ruta completa `/opt/homebrew/bin/flutter` |

---

## Directorios TS Cubiertos (11/36)

`types/` `constants/` `bootstrap/` `services/api/` `services/oauth/` `entrypoints/` `state/` `context/` `schemas/` `moreright/` `outputStyles/`
