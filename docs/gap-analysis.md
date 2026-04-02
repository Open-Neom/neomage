# Gap Analysis — TypeScript vs Dart Port

## Reality Check

| | TypeScript (Original) | Dart (Port) | Ratio |
|---|---|---|---|
| **Files** | 1,921 | 110 | 17:1 |
| **LOC** | 517,610 | 17,173 | 30:1 |

**30:1 no es compresión legítima.** Es código faltante. A continuación el desglose exacto.

---

## What's Missing — By Directory

### 1. `utils/` — 182,151 LOC TS → ~650 LOC Dart (99.6% missing)

| Subdirectory | TS LOC | Ported? | Gap |
|---|---|---|---|
| `utils/plugins/` | 20,521 | ~30 LOC stub | Plugin install, discovery, test, lint, bundling |
| `utils/bash/` | 12,306 | 96 LOC | Bash sandboxing, output parsing, ANSI stripping, pty management |
| `utils/permissions/` | 9,409 | ~220 LOC | Permission DB, rule engine, glob matching, tool-specific rules |
| `utils/swarm/` | 7,548 | ❌ | Multi-agent swarm orchestration |
| `utils/settings/` | 4,562 | 53 LOC | Settings schema validation, migration, sync, scoped settings |
| `utils/telemetry/` | 4,044 | ❌ | Telemetry pipeline, event batching, Sentry integration |
| `utils/hooks/` | 3,721 | ❌ | Hook loading, validation, execution sandbox, timeout handling |
| `utils/shell/` | 3,069 | ❌ | Shell detection, profile loading, env inheritance, PTY |
| `utils/model/` | 3,046 | ❌ | Model catalog, pricing, capability detection, token counting |
| `utils/nativeInstaller/` | 3,018 | ❌ | System installation scripts (brew, apt, etc.) |
| `utils/claudeInChrome/` | 2,337 | ❌ | Chrome extension bridge |
| `utils/powershell/` | 2,305 | ❌ | PowerShell execution, parsing |
| `utils/computerUse/` | 2,161 | ❌ | Computer use tool (screenshots, mouse, keyboard) |
| `utils/processUserInput/` | 1,765 | ❌ | Input parsing, @-mentions, file references, command detection |
| `utils/deepLink/` | 1,388 | ❌ | Deep link URL scheme handling |
| `utils/task/` | 1,223 | ❌ | Task lifecycle, dependency graph, parallelism |
| `utils/suggestions/` | 1,213 | ~186 LOC | Suggestion filtering, context-aware prompts |
| `utils/git/` | 1,075 | 255 LOC | Partial — missing PR creation, diff parsing, blame |
| `utils/sandbox/` | 997 | ❌ | Docker/sandbox execution environment |
| `utils/teleport/` | 955 | ❌ | Session teleportation between machines |
| Other (12 dirs) | ~5,000 | ❌ | Various small utilities |

**Estimated gap: ~170,000 LOC equivalent → ~25,000 LOC Dart needed**

---

### 2. `components/` — 81,779 LOC TS → ~2,200 LOC Dart (97% missing)

| Subdirectory | TS LOC | Ported? | Gap |
|---|---|---|---|
| `permissions/` | 12,155 | 292 LOC | Full permission UI with rule editor, history, trust management |
| `messages/` | 6,016 | 652 LOC | System/attachment/error/progress message types, image preview |
| `PromptInput/` | 5,161 | 107 LOC | Autocomplete, history, multi-line, @-mentions, file picker |
| `agents/` | 4,527 | ❌ | Agent status panel, progress, task tree |
| `tasks/` | 3,940 | ❌ | Task list UI, progress bars, dependency visualization |
| `mcp/` | 3,920 | ❌ | MCP server status, tool browser, resource viewer |
| `CustomSelect/` | 3,019 | ❌ | Fuzzy-search select component |
| `Settings/` | 2,573 | 224 LOC | Settings tabs, model picker, API key management |
| `LogoV2/` | 2,490 | ❌ | Animated logo/splash |
| `design-system/` | 2,236 | ❌ | Design tokens, shared components |
| `Spinner/` | 1,469 | ❌ | Animated spinners with verb cycling |
| `FeedbackSurvey/` | 1,372 | ❌ | In-app feedback collection |
| `hooks/` | 1,244 | ❌ | React hooks for state management |
| `diff/` | 953 | 582 LOC | Word-level diff, side-by-side view |
| `teams/` | 793 | ❌ | Team collaboration UI |
| Other (16+ dirs) | ~10,000 | ❌ | Various UI components |

**Estimated gap: ~70,000 LOC equivalent → ~12,000 LOC Dart needed**

---

### 3. `services/` — 56,312 LOC TS → ~1,500 LOC Dart (97% missing)

| Subdirectory | TS LOC | Ported? | Gap |
|---|---|---|---|
| `api/` | 13,071 | ~850 LOC | Streaming, multimodal, beta features, prompt caching |
| `mcp/` | 12,320 | 774 LOC | Full MCP protocol, SSE/HTTP/WS transports, auth |
| `analytics/` | 4,040 | 320 LOC | Event pipeline, batching, Sentry, PostHog |
| `compact/` | 3,976 | 271 LOC | Advanced compaction strategies, scoring |
| `tools/` | 3,113 | ❌ | Tool execution service, sandboxing, output limits |
| `lsp/` | 2,460 | 540 LOC | Good coverage |
| `teamMemorySync/` | 2,167 | ❌ | Team shared memory synchronization |
| `plugins/` | 1,616 | 156 LOC | Plugin lifecycle, hot reload, dependency resolution |
| `PromptSuggestion/` | 1,514 | 186 LOC | Partial |
| `oauth/` | 1,051 | 217 LOC | Partial — missing token refresh, PKCE full flow |
| `SessionMemory/` | 1,026 | 259 LOC | Partial |
| `remoteManagedSettings/` | 950 | ❌ | Enterprise settings sync |
| `extractMemories/` | 769 | ❌ | Memory extraction from conversations |
| `tips/` | 761 | 146 LOC | Partial |
| `policyLimits/` | 690 | 149 LOC | Partial |
| `settingsSync/` | 648 | ❌ | Cross-device settings sync |
| `autoDream/` | 550 | ❌ | Background processing during idle |
| Other (4 dirs) | ~700 | ❌ | Various services |

**Estimated gap: ~48,000 LOC equivalent → ~7,500 LOC Dart needed**

---

### 4. `tools/` — 50,901 LOC TS → ~1,371 LOC Dart (97% missing)

| Tool | TS LOC | Dart LOC | Gap |
|---|---|---|---|
| `BashTool/` | 12,411 | 96 | Sandbox, PTY, timeout, ANSI, output limits |
| `PowerShellTool/` | 8,959 | ❌ | Entire PowerShell tool |
| `AgentTool/` | 6,782 | 476 | Worktree isolation, background execution |
| `LSPTool/` | 2,005 | ❌ | LSP tool for code intelligence |
| `FileEditTool/` | 1,812 | 93 | Validation, conflict detection, undo |
| `FileReadTool/` | 1,602 | 69 | Image/PDF/notebook reading, pagination |
| `SkillTool/` | 1,477 | ❌ | Skill invocation tool |
| `WebFetchTool/` | 1,131 | ❌ | HTTP fetching, HTML parsing |
| `MCPTool/` | 1,086 | ❌ | MCP tool proxy |
| `SendMessageTool/` | 997 | 130 | Inter-agent messaging details |
| `FileWriteTool/` | 856 | 56 | Write guards, backup, permissions |
| `ConfigTool/` | 809 | ❌ | Runtime configuration tool |
| `GrepTool/` | 795 | 122 | Multiline, ripgrep integration |
| `NotebookEditTool/` | 587 | ❌ | Jupyter notebook editing |
| `TaskOutputTool/` | 584 | 179 | Partial |
| `WebSearchTool/` | 569 | ❌ | Web search tool |
| `ToolSearchTool/` | 593 | 273 | Good coverage |
| Other (29 tools) | ~9,000 | ❌ | Various tools |

**Estimated gap: ~45,000 LOC equivalent → ~7,000 LOC Dart needed**

---

### 5. `commands/` — 26,434 LOC TS → ~514 LOC Dart (98% missing)

We ported 12 commands as stubs. Original has **88 commands**:

**Completely Missing Commands (76):**
- `plugin/` (7,575 LOC) — install, create, list, test, publish
- `install-github-app/` (2,352 LOC) — GitHub App installation flow
- `ide/` (656 LOC) — IDE integration setup
- `mcp/` (642 LOC) — MCP server management
- `thinkback/` (566 LOC) — Thinking playback
- `remote-setup/` (388 LOC) — Remote environment setup
- `copy/` (385 LOC) — Copy to clipboard
- `voice/` (170 LOC) — Voice input toggle
- `mobile/` (284 LOC) — Mobile mode setup
- `fast/` (294 LOC) — Fast mode toggle
- `add-dir/` (246 LOC) — Add working directory
- Plus 65 more commands...

**Estimated gap: ~24,000 LOC equivalent → ~4,000 LOC Dart needed**

---

### 6. Other Missing Directories

| Directory | TS LOC | Ported? | What's Missing |
|---|---|---|---|
| `ink/` | 19,896 | ❌ | Terminal UI framework (not needed for Flutter, but logic layer is) |
| `hooks/` (React) | 19,219 | ❌ | 105 React hooks → need Sint controllers equivalent |
| `bridge/` | 12,613 | ❌ | IDE bridge protocol (VS Code, JetBrains) |
| `cli/` | 12,353 | 210 LOC | CLI handlers, transport layer |
| `screens/` | 5,973 | ~650 LOC | Full screen implementations |
| `skills/` | 4,233 | 251 LOC | Bundled skills, skill runtime |
| `entrypoints/` | 4,123 | 109 LOC | SDK entrypoints |
| `native-ts/` | 4,081 | ❌ | Yoga layout, color-diff native, file index |
| `types/` | 3,464 | ~1,054 LOC | Partial domain models |
| `tasks/` | 3,286 | ❌ | Task types (Dream, Teammate, Local, Remote) |
| `keybindings/` | 3,159 | 330 LOC | Partial |
| `vim/` | 1,513 | ❌ | Vim mode |
| `bootstrap/` | 1,758 | 102 LOC | State initialization |
| `state/` | 1,192 | ❌ | Global state management |
| `context/` | 1,004 | ❌ | React contexts → need Sint equivalents |
| `remote/` | 1,127 | 305 LOC | Partial |
| Root files | 11,957 | ~170 LOC | QueryEngine, Task, Tool, cost-tracker, etc. |
| Other dirs | ~2,500 | ❌ | Various small modules |

**Estimated gap: ~80,000 LOC equivalent → ~12,000 LOC Dart needed**

---

## Summary — True Gap

| Category | TS LOC | Dart LOC | Missing TS LOC | Dart Needed |
|---|---|---|---|---|
| **utils/** | 182,151 | 650 | 181,500 | ~25,000 |
| **components/** | 81,779 | 2,200 | 79,500 | ~12,000 |
| **services/** | 56,312 | 1,500 | 54,800 | ~7,500 |
| **tools/** | 50,901 | 1,371 | 49,500 | ~7,000 |
| **commands/** | 26,434 | 514 | 25,900 | ~4,000 |
| **Other dirs** | 120,033 | 10,938 | 109,000 | ~12,000 |
| **TOTAL** | **517,610** | **17,173** | **500,200** | **~67,500** |

### Real Compression Ratio
- **Legitimate TS→Dart compression**: ~7:1 (removing React/Ink/Node boilerplate, type assertions, JSX→widgets)
- **Expected Dart total for full port**: ~70,000 LOC
- **Currently ported**: ~17,173 LOC
- **Completion**: **~24.5%**

### What accounts for the 7:1 compression?
1. React/JSX component wrappers → Flutter widgets (3:1)
2. TypeScript type assertions and guards → Dart sealed classes (2:1)
3. Node.js/Ink terminal framework → eliminated (ink/ is 19,896 LOC of terminal UI)
4. Import/export boilerplate → Dart barrels (minor)
5. Test files mixed in with source (some dirs have .test.ts files)

### Priority Order for Remaining Work
1. **Tools** (BashTool full, WebFetch, WebSearch, Notebook, PowerShell, LSP, Skill, Config) — ~7,000 LOC
2. **Utils** (bash, permissions, shell, model, processUserInput, settings) — ~25,000 LOC
3. **Services** (api streaming, mcp full, tools service, team sync) — ~7,500 LOC
4. **Commands** (remaining 76 commands) — ~4,000 LOC
5. **UI Components** (agents, tasks, MCP panel, prompt input, design system) — ~12,000 LOC
6. **Infrastructure** (bridge, cli, tasks, vim, state, context) — ~12,000 LOC
