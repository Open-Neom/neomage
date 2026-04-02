# Fase 3 Report — Commands, Analytics, Services

## Overview
Phase 3 ported the command system, analytics infrastructure, feature flags, and supporting services. This phase bridges the gap between the core engine and user-facing features.

**Duration**: ~1 session
**Files Created**: 20
**LOC Added**: ~2,800

## Modules Ported

### Command System (8 files)
| File | LOC | Description |
|------|-----|-------------|
| `data/commands/command.dart` | 145 | Base types: CommandType, CommandSource, CommandResult (sealed) |
| `data/commands/command_registry.dart` | 85 | Registry with search, typeahead, by-type filtering |
| `builtin/clear_command.dart` | 28 | `/clear` with aliases `reset`, `new` |
| `builtin/compact_command.dart` | 35 | `/compact` triggering CompactionService |
| `builtin/help_command.dart` | 65 | `/help` with per-command detail and full listing |
| `builtin/model_command.dart` | 42 | `/model` with ModelChanger callback |
| `builtin/context_command.dart` | 38 | `/context` showing token usage |
| `builtin/cost_command.dart` | 40 | `/cost` showing session costs |
| `builtin/memory_command.dart` | 55 | `/memory` with list/show/delete subcommands |
| `builtin/commit_command.dart` | 30 | `/commit` as PromptCommand |
| `builtin/review_command.dart` | 45 | `/review` supporting PR numbers and file paths |
| `builtin/plan_command.dart` | 35 | `/plan` toggle with callback |
| `builtin/session_command.dart` | 50 | `/session` with list/current/delete |
| `builtin/diff_command.dart` | 25 | `/diff` as PromptCommand |

### Analytics & Feature Flags (2 files)
| File | LOC | Description |
|------|-----|-------------|
| `data/analytics/analytics_service.dart` | 220 | AnalyticsSink (abstract), InMemory + File sinks, 17 event constants |
| `data/analytics/feature_flags.dart` | 195 | FeatureFlag<T> generic, remote refresh, 13 GrowthBook keys |

### Services (4 files)
| File | LOC | Description |
|------|-----|-------------|
| `data/services/tips_service.dart` | 175 | 10 built-in tips, cooldown, priority by staleness |
| `data/services/prompt_suggestion_service.dart` | 180 | 13 filter rules, suppression checks |
| `data/services/rate_limit_service.dart` | 160 | PolicyLimit, cache + remote fetch, fail-open design |
| `data/services/coordinator_service.dart` | 145 | Task tracking, synthesis prompt building |

## Key Decisions
1. **Three command types**: PromptCommand (LLM), LocalCommand (sync), LocalUiCommand (Flutter UI)
2. **Sealed CommandResult**: Text/Compact/Skip — no ambiguous returns
3. **Provider-agnostic analytics**: Abstract AnalyticsSink allows any backend
4. **Feature flags generic**: `FeatureFlag<T>` supports bool, string, int, JSON

## Export Conflicts Resolved
- `CommandType`, `Command`, `PromptCommand` existed in both `domain/models/command.dart` and `data/commands/command.dart`
- Fixed with selective `show` clause on the domain export

## Bugs Fixed
- Unused `dart:math` import in tips_service.dart
- Unused `message.dart` import in coordinator_service.dart
