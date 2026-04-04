# Fase 2: Tool System + Query Engine — Reporte Completo

**Proyecto:** flutter_claw (Open Neom)
**Fuente:** NeomClaw (~517,610 LOC TypeScript, 1,921 archivos)
**Fecha de inicio:** Abril 2026
**Fecha de cierre Fase 2:** Abril 2026
**Estado:** COMPLETADA

---

## Resumen Ejecutivo

La Fase 2 portó el sistema completo de herramientas agénticas (P1 + P2), el sistema de memoria persistente (memdir), la gestión de sesiones con persistencia y restauración, el servicio de compactación de contexto de 3 fases, y mejoró el QueryEngine con permission checking, compaction integrada, y session memory tracking. Se agregó UI para permisos y visualización de tool outputs.

---

## Métricas al cierre de Fase 2

| Métrica | Fase 1 | Fase 2 | Delta |
|---------|--------|--------|-------|
| Archivos Dart | ~52 | 68 | +16 |
| LOC Dart | ~5,500 | 8,965 | +3,465 |
| Tools portados | 6 (P1) | 11 (P1+P2) | +5 |
| Directorios TS cubiertos | 11/36 | 19/36 | +8 |
| Issues `flutter analyze` | 2 info | 2 info | = |

---

## Módulos Migrados

### 1. Agent Tools — P2 (`lib/data/tools/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `agent_tool.dart` | 476 | `src/tools/AgentTool/` (~6,782 LOC TS) | Sub-agent spawning con loop agentico propio, 3 built-in agents (general-purpose, Explore, Plan), foreground/background execution, custom agent registration, tool resolution per agent |
| `send_message_tool.dart` | 130 | `src/tools/SendMessageTool/` (~997 LOC TS) | Message routing entre agents, cola de pending messages, consume/check API |
| `task_output_tool.dart` | 179 | `src/tools/TaskOutputTool/` (~584 LOC TS) | Background task retrieval, blocking/non-blocking modes, poll con timeout (max 600s), TrackedTask con status machine |
| `todo_write_tool.dart` | 165 | `src/tools/TodoWriteTool/` (~300 LOC TS) | TodoItem con content/activeForm/status, TodoStatus enum, auto-clear on all-completed, per-key storage, persistence callback |
| `tool_search_tool.dart` | 273 | `src/tools/ToolSearchTool/` (~593 LOC TS) | Deferred tool discovery, direct selection (`select:A,B`), keyword search con scoring (exact:12, substring:6, name:4, desc:2), CamelCase + MCP name parsing, `+required` term filtering |

**Arquitectura del AgentTool:**

```
AgentTool.execute()
  ├─ _resolveAgent() → BuiltInAgents / customAgents
  ├─ _resolveAgentTools() → filter by allowed/disallowed, remove recursive Agent
  ├─ runInBackground?
  │   ├─ true → _launchBackground() → unawaited(_runAgent())
  │   └─ false → await _runAgent()
  └─ _runAgent()
       └─ Agentic loop (max 25 turns):
            provider.createMessage() → extract toolUses → execute tools → inject results
```

**Built-in Agents:**

| Agent | Tools Allowed | Tools Blocked | Uso |
|-------|---------------|---------------|-----|
| general-purpose | All | Agent (no recursion) | Multi-step tasks |
| Explore | Read, Glob, Grep, Bash, WebSearch, WebFetch | Agent, Edit, Write, NotebookEdit | Codebase exploration |
| Plan | All except blocked | Agent, Edit, Write, NotebookEdit | Architecture planning |

### 2. Context Compaction (`lib/data/compact/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `compaction_service.dart` | 271 | `src/services/compact/` (~4,000 LOC TS, 13 archivos) | 3-phase compaction consolidado en un solo servicio |

**Sistema de 3 fases:**

```
Fase 1: Microcompaction (pre-API, sin LLM)
  └─ Limpia tool results antiguos, mantiene últimos 5
  └─ compactableTools: Read, Bash, Grep, Glob, WebSearch, WebFetch, Edit, Write

Fase 2: Auto-compact trigger
  └─ shouldAutoCompact(): contextWindow - 13,000 buffer tokens
  └─ Circuit breaker: max 3 consecutive failures

Fase 3: Full compaction (LLM summarization)
  └─ _generateSummary(): prompt especializado con 7 focos
  └─ Transcript builder: role labels, tool use/result previews (500 char)
  └─ Output: "[Conversation compacted. Summary of prior context:]"
```

### 3. Memdir — Persistent Memory (`lib/data/memdir/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `memory_types.dart` | ~80 | `src/memdir/memoryTypes.ts` | MemoryType enum (user/feedback/project/reference), MemoryFrontmatter, parseFrontmatter() YAML parser |
| `memory_scan.dart` | ~80 | `src/memdir/memoryScan.ts` | MemoryHeader, scanMemoryFiles() recursive, formatMemoryManifest() con age tracking |
| `memdir_paths.dart` | ~80 | `src/memdir/paths.ts` | getMemoryBaseDir(), getAutoMemPath(), validateMemoryPath() con security checks (null bytes, traversal, root), ensureMemoryDirExists() |
| `memdir_service.dart` | 215 | `src/memdir/memdir.ts` | MemdirService: initialize(), loadMemoryPrompt(), writeMemoryFile() con frontmatter, readEntrypoint(), scanMemories(), deleteMemoryFile(), _buildMemoryPrompt() |

**Path resolution:**

```
ENV CLAUDE_COWORK_MEMORY_PATH_OVERRIDE (full override)
  └─ fallback: ~/.claude/projects/{sanitized-git-root}/memory/
       └─ MEMORY.md (entrypoint, max 200 lines / 25KB)
       └─ *.md (individual memories with frontmatter)
```

**Security validations:**
- Rejects null bytes, relative paths, root/near-root paths
- Normalizes paths before validation
- Path traversal protection (`..` rejection)

### 4. Session System (`lib/data/session/`)

| Archivo | LOC | Origen TS | Descripción |
|---------|-----|-----------|-------------|
| `session_memory.dart` | 259 | `src/services/SessionMemory/` (~1,029 LOC TS) | Background extraction con thresholds (10K init, 5K update, 3 tool calls), 10 template sections, file reference extraction, error extraction |
| `session_history.dart` | 216 | `src/assistant/sessionHistory.ts` + `src/utils/` | SessionSnapshot JSON persistence, save/load/list/delete, full message serialization (ContentBlock→JSON→ContentBlock), modification-time sorting |
| `session_restore.dart` | ~100 | `src/utils/sessionRestore.ts` (~552 LOC TS) | RestoredSession, todo extraction from TodoWrite blocks, file reference extraction from text + tool inputs, CWD recovery from Bash `cd` commands |

**Session Memory template sections:**

```
1. Task          2. Current State     3. Key Files
4. Workflow      5. Errors & Fixes    6. Technical Decisions
7. User Preferences  8. Pending Items  9. Dependencies  10. Notes
```

**Session restore flow:**

```
SessionSnapshot → restoreSession()
  ├─ _extractTodos() → scan for last TodoWrite tool_use block
  ├─ _extractFileReferences() → regex on text + file_path/path from tool inputs
  └─ _extractWorkingDirectory() → last Bash "cd /absolute/path"
```

### 5. Enhanced Tool Base (`lib/data/tools/tool.dart`)

Mejoras sobre Fase 1:

| Feature | Descripción |
|---------|-------------|
| Permission system | `checkPermissions()` → PermissionDecision (sealed: Allow/Ask/Deny) |
| Safety flags | `isReadOnly`, `isDestructive`, `isConcurrencySafe`, `requiresUserInteraction` |
| Interrupt behavior | `InterruptBehavior` enum: interruptible, finishThenYield, nonInterruptible |
| Deferred tools | `shouldDefer`, `alwaysLoad` — ToolSearch loads on demand |
| MCP support | `isMcp`, `mcpInfo` — for future MCP tool integration |
| Result handling | `maxResultSizeChars`, `strict` JSON output |
| Activity display | `getToolUseSummary()`, `getActivityDescription()` |
| Context execution | `call(input, ToolUseContext)` with AbortSignal, CWD, debug mode |

**3 Mixins:**

```dart
ShellToolMixin    → isDestructive=true, finishThenYield
ReadOnlyToolMixin → isReadOnly=true, isConcurrencySafe=true, auto-allow
FileWriteToolMixin → isDestructive=true
```

### 6. Enhanced QueryEngine (`lib/data/engine/query_engine.dart`)

| Feature | Descripción |
|---------|-------------|
| QueryEngineConfig | maxTurns, contextWindow, enableCompaction, enableMicrocompact, enableSessionMemory |
| Microcompact | Pre-API clearing de old tool results (Phase 1) |
| Auto-compact | Threshold-based full compaction trigger (Phase 2+3) |
| Permission checking | Tool.checkPermissions() → Allow/Deny/Ask → OnPermissionRequest callback |
| Session memory | trackMessage() on every assistant + user message |
| OnCompaction callback | Notifica cuando se ejecuta compaction |

**Enhanced agentic loop:**

```
while (turn < maxTurns):
  1. microcompact(messages)           ← Phase 1 compaction
  2. autoCompactIfNeeded(messages)    ← Phase 2+3 compaction
  3. streamOneRound() → assistant msg
  4. sessionMemory.trackMessage()
  5. for each toolUse:
     a. checkPermission() → Allow/Ask/Deny
     b. if Deny → inject error result
     c. onToolUse callback
     d. toolRegistry.execute()
     e. onToolResult callback
  6. inject tool results as user message
  7. sessionMemory.trackMessage()
```

### 7. Permission UI (`lib/ui/widgets/`)

| Archivo | LOC | Descripción |
|---------|-----|-------------|
| `permission_dialog.dart` | 292 | Full modal dialog: risk badge (Low/Medium/High con color + icono), tool input preview (monospace, 15 lines max), remember checkboxes (session/project), Allow/Deny buttons. Inline `PermissionBanner` alternativo para lower-risk ops |
| `tool_output_widget.dart` | 194 | Expandable tool result cards: per-tool icons (12 tools), smart input summary (file_path para Read/Edit, command para Bash, pattern para Grep), error styling, max-height scroll, `ToolProgressIndicator` spinner |

---

## Tool Inventory (11 tools completados)

### P1 — Core Tools (6)

| Tool | Mixin | LOC | Descripción |
|------|-------|-----|-------------|
| Bash | ShellToolMixin | ~70 | Process.run, timeout, working directory |
| Read | ReadOnlyToolMixin | ~70 | File read con line numbers, offset/limit |
| Write | FileWriteToolMixin | ~56 | File write, parent dir creation |
| Edit | FileWriteToolMixin | ~93 | String replacement, uniqueness check, replace_all |
| Grep | ReadOnlyToolMixin | ~122 | RegExp recursive search, glob filter |
| Glob | ReadOnlyToolMixin | ~104 | Pattern matching, extension extraction, sort by mtime |

### P2 — Agent Tools (5)

| Tool | Type | LOC | Descripción |
|------|------|-----|-------------|
| Agent | Standard | 476 | Sub-agent spawn, 3 built-ins, background exec |
| SendMessage | ReadOnly | 130 | Inter-agent messaging, queue |
| TaskOutput | ReadOnly | 179 | Background task polling, timeout |
| TodoWrite | Standard | 165 | Task list management, auto-clear |
| ToolSearch | ReadOnly | 273 | Deferred tool discovery, scoring |

---

## Estructura de Archivos al Cierre de Fase 2

```
lib/ (68 archivos, 8,965 LOC)
├── main.dart
├── root_binding.dart
├── claw_routes.dart
├── flutter_claw.dart
├── data/
│   ├── api/
│   │   ├── api_provider.dart         (138)
│   │   ├── anthropic_client.dart     (247)
│   │   ├── openai_shim.dart          (401)
│   │   ├── errors.dart               (252)
│   │   └── retry.dart                (176)
│   ├── auth/
│   │   ├── auth_service.dart
│   │   └── oauth_service.dart        (217)
│   ├── bootstrap/
│   │   └── app_state.dart
│   ├── compact/
│   │   └── compaction_service.dart    (271) ← NEW
│   ├── engine/
│   │   └── query_engine.dart         (301) ← ENHANCED
│   ├── memdir/                       ← NEW
│   │   ├── memdir_paths.dart
│   │   ├── memdir_service.dart       (215)
│   │   ├── memory_scan.dart
│   │   └── memory_types.dart
│   ├── session/                      ← NEW
│   │   ├── session_history.dart      (216)
│   │   ├── session_memory.dart       (259)
│   │   └── session_restore.dart
│   └── tools/
│       ├── tool.dart                 (229) ← ENHANCED
│       ├── tool_registry.dart         (47)
│       ├── bash_tool.dart
│       ├── file_read_tool.dart
│       ├── file_write_tool.dart
│       ├── file_edit_tool.dart
│       ├── grep_tool.dart
│       ├── glob_tool.dart
│       ├── agent_tool.dart           (476) ← NEW
│       ├── send_message_tool.dart    (130) ← NEW
│       ├── task_output_tool.dart     (179) ← NEW
│       ├── todo_write_tool.dart      (165) ← NEW
│       └── tool_search_tool.dart     (273) ← NEW
├── domain/models/
│   ├── message.dart, permissions.dart, hooks.dart,
│   ├── logs.dart, command.dart, plugin.dart,
│   ├── entrypoints.dart, hook_schemas.dart,
│   ├── ids.dart, tool_definition.dart
├── ui/
│   ├── controllers/
│   │   └── chat_controller.dart
│   ├── screens/
│   │   ├── chat_screen.dart, onboarding_screen.dart,
│   │   ├── settings_screen.dart, splash_screen.dart
│   ├── widgets/
│   │   ├── message_bubble.dart, streaming_text.dart,
│   │   ├── input_bar.dart,
│   │   ├── permission_dialog.dart    (292) ← NEW
│   │   └── tool_output_widget.dart   (194) ← NEW
│   └── theme/
│       └── app_theme.dart
└── utils/
    ├── config/settings.dart
    └── constants/ (12 archivos)
```

---

## Directorios TS Cubiertos (19/36)

**Fase 1 (11):** `types/` `constants/` `bootstrap/` `services/api/` `services/oauth/` `entrypoints/` `state/` `context/` `schemas/` `moreright/` `outputStyles/`

**Fase 2 (+8):** `tools/` (parcial: 11/48) `query/` `services/compact/` `services/tools/` `services/SessionMemory/` `assistant/` `memdir/` `migrations/`

---

## Métricas de Compresión TS→Dart

| Módulo TS | LOC TS | LOC Dart | Ratio |
|-----------|--------|----------|-------|
| AgentTool (10 archivos) | ~6,782 | 476 | 14:1 |
| Compact (13 archivos) | ~4,000 | 271 | 15:1 |
| SessionMemory (3 archivos) | ~1,029 | 259 | 4:1 |
| ToolSearchTool | ~593 | 273 | 2:1 |
| Session restore | ~552 | ~100 | 6:1 |
| Tool.ts base | ~800 | 229 | 3.5:1 |

**Promedio:** ~7:1 compresión. Las mayores compresiones vienen de eliminar boilerplate de React/Ink UI, type assertions de TypeScript, y consolidar archivos múltiples en uno.

---

## Próximos Pasos — Fase 3

La Fase 3 cubrirá:
- 75+ slash commands (`/commit`, `/review`, `/plan`, `/tasks`, etc.)
- Analytics (GrowthBook, Datadog, event logging)
- Session persistence con sqflite
- Command palette widget
- `coordinator/` mode
- `tasks/` system
- `buddy/` system
- Tips, suggestions, rate limits, remote settings, memory extraction, team memory sync
