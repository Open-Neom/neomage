/// Hook Manager
///
/// Ported from neomage/src/utils/hooks/:
///   - sessionHooks.ts    — session-scoped hook lifecycle
///   - hooksConfigManager.ts — hook event metadata and grouping
///   - hooksSettings.ts   — hook settings, sources, equality, display
///   - hookEvents.ts      — hook event emission system
///   - AsyncHookRegistry.ts — async hook tracking
///   - ssrfGuard.ts       — SSRF address blocking for HTTP hooks
///
/// Provides the full hook lifecycle for the Sint-based Flutter port:
///   session hooks, function hooks, event metadata, config grouping,
///   hook emission, async hook registry, and SSRF protection.
library;

import 'dart:async';

// ---------------------------------------------------------------------------
// Hook event types (from agentSdkTypes)
// ---------------------------------------------------------------------------

/// All supported hook event names.
const List<String> hookEvents = [
  'PreToolUse',
  'PostToolUse',
  'PostToolUseFailure',
  'PermissionDenied',
  'Notification',
  'UserPromptSubmit',
  'SessionStart',
  'SessionEnd',
  'Stop',
  'StopFailure',
  'SubagentStart',
  'SubagentStop',
  'PreCompact',
  'PostCompact',
  'PermissionRequest',
  'Setup',
  'TeammateIdle',
  'TaskCreated',
  'TaskCompleted',
  'Elicitation',
  'ElicitationResult',
  'ConfigChange',
  'WorktreeCreate',
  'WorktreeRemove',
  'InstructionsLoaded',
  'CwdChanged',
  'FileChanged',
];

typedef HookEvent = String;

// ---------------------------------------------------------------------------
// Hook command types
// ---------------------------------------------------------------------------

/// Base type for all hook commands.
abstract class HookCommand {
  String get type;
  int? get timeout;
  String? get ifCondition;
}

/// Shell command hook.
class CommandHook implements HookCommand {
  @override
  final String type = 'command';
  final String command;
  final String? shell;
  @override
  final int? timeout;
  @override
  final String? ifCondition;

  const CommandHook({
    required this.command,
    this.shell,
    this.timeout,
    this.ifCondition,
  });
}

/// Prompt hook (LLM evaluates a prompt).
class PromptHook implements HookCommand {
  @override
  final String type = 'prompt';
  final String prompt;
  @override
  final int? timeout;
  @override
  final String? ifCondition;

  const PromptHook({required this.prompt, this.timeout, this.ifCondition});
}

/// Agent hook (multi-turn LLM agent).
class AgentHook implements HookCommand {
  @override
  final String type = 'agent';
  final String prompt;
  final String? model;
  @override
  final int? timeout;
  @override
  final String? ifCondition;

  const AgentHook({
    required this.prompt,
    this.model,
    this.timeout,
    this.ifCondition,
  });
}

/// HTTP hook (sends request to URL).
class HttpHook implements HookCommand {
  @override
  final String type = 'http';
  final String url;
  @override
  final int? timeout;
  @override
  final String? ifCondition;

  const HttpHook({required this.url, this.timeout, this.ifCondition});
}

/// Function hook (in-memory callback, session-scoped only).
class FunctionHook implements HookCommand {
  @override
  final String type = 'function';
  final String? id;
  @override
  final int? timeout;
  @override
  final String? ifCondition = null;
  final Future<bool> Function(List<dynamic> messages, {Object? signal})
  callback;
  final String errorMessage;
  final String? statusMessage;

  FunctionHook({
    required this.callback,
    required this.errorMessage,
    this.id,
    this.timeout,
    this.statusMessage,
  });
}

// ---------------------------------------------------------------------------
// Hook equality and display (from hooksSettings.ts)
// ---------------------------------------------------------------------------

/// Default shell for command hooks.
const String defaultHookShell = 'bash';

/// Check if two hooks are equal (comparing command/prompt content, not timeout).
bool isHookEqual(HookCommand a, HookCommand b) {
  if (a.type != b.type) return false;

  final sameIf = (a.ifCondition ?? '') == (b.ifCondition ?? '');

  if (a is CommandHook && b is CommandHook) {
    return a.command == b.command &&
        (a.shell ?? defaultHookShell) == (b.shell ?? defaultHookShell) &&
        sameIf;
  }
  if (a is PromptHook && b is PromptHook) {
    return a.prompt == b.prompt && sameIf;
  }
  if (a is AgentHook && b is AgentHook) {
    return a.prompt == b.prompt && sameIf;
  }
  if (a is HttpHook && b is HttpHook) {
    return a.url == b.url && sameIf;
  }
  if (a is FunctionHook) {
    return false; // Function hooks can't be compared
  }
  return false;
}

/// Get the display text for a hook.
String getHookDisplayText(HookCommand hook) {
  if (hook is FunctionHook && hook.statusMessage != null) {
    return hook.statusMessage!;
  }
  if (hook is CommandHook) return hook.command;
  if (hook is PromptHook) return hook.prompt;
  if (hook is AgentHook) return hook.prompt;
  if (hook is HttpHook) return hook.url;
  if (hook is FunctionHook) return 'function';
  return 'unknown';
}

// ---------------------------------------------------------------------------
// Hook source types (from hooksSettings.ts)
// ---------------------------------------------------------------------------

/// Source of a hook configuration.
enum HookSource {
  userSettings,
  projectSettings,
  localSettings,
  policySettings,
  pluginHook,
  sessionHook,
  builtinHook,
}

/// Display strings for hook sources.
String hookSourceDescription(HookSource source) {
  switch (source) {
    case HookSource.userSettings:
      return 'User settings (~/.neomage/settings.json)';
    case HookSource.projectSettings:
      return 'Project settings (.neomage/settings.json)';
    case HookSource.localSettings:
      return 'Local settings (.neomage/settings.local.json)';
    case HookSource.pluginHook:
      return 'Plugin hooks (~/.neomage/plugins/*/hooks/hooks.json)';
    case HookSource.sessionHook:
      return 'Session hooks (in-memory, temporary)';
    case HookSource.builtinHook:
      return 'Built-in hooks (registered internally by Neomage)';
    case HookSource.policySettings:
      return 'Policy settings';
  }
}

String hookSourceHeader(HookSource source) {
  switch (source) {
    case HookSource.userSettings:
      return 'User Settings';
    case HookSource.projectSettings:
      return 'Project Settings';
    case HookSource.localSettings:
      return 'Local Settings';
    case HookSource.pluginHook:
      return 'Plugin Hooks';
    case HookSource.sessionHook:
      return 'Session Hooks';
    case HookSource.builtinHook:
      return 'Built-in Hooks';
    case HookSource.policySettings:
      return 'Policy Settings';
  }
}

String hookSourceInline(HookSource source) {
  switch (source) {
    case HookSource.userSettings:
      return 'User';
    case HookSource.projectSettings:
      return 'Project';
    case HookSource.localSettings:
      return 'Local';
    case HookSource.pluginHook:
      return 'Plugin';
    case HookSource.sessionHook:
      return 'Session';
    case HookSource.builtinHook:
      return 'Built-in';
    case HookSource.policySettings:
      return 'Policy';
  }
}

// ---------------------------------------------------------------------------
// Individual hook config (from hooksSettings.ts)
// ---------------------------------------------------------------------------

/// A single hook configuration with its source and event info.
class IndividualHookConfig {
  final HookEvent event;
  final HookCommand config;
  final String? matcher;
  final HookSource source;
  final String? pluginName;

  const IndividualHookConfig({
    required this.event,
    required this.config,
    this.matcher,
    required this.source,
    this.pluginName,
  });
}

// ---------------------------------------------------------------------------
// Session hooks (from sessionHooks.ts)
// ---------------------------------------------------------------------------

/// A single matcher entry in the session hook store.
class SessionHookMatcher {
  final String matcher;
  final String? skillRoot;
  final List<SessionHookEntry> hooks;

  SessionHookMatcher({
    required this.matcher,
    this.skillRoot,
    required this.hooks,
  });
}

/// An entry pairing a hook with its optional success callback.
class SessionHookEntry {
  final HookCommand hook;
  final void Function(HookCommand hook, AggregatedHookResult result)?
  onHookSuccess;

  const SessionHookEntry({required this.hook, this.onHookSuccess});
}

/// Aggregated result from hook execution.
class AggregatedHookResult {
  final String stdout;
  final String stderr;
  final int exitCode;

  const AggregatedHookResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}

/// Session hook store per session.
class SessionStore {
  final Map<HookEvent, List<SessionHookMatcher>> hooks;

  SessionStore({Map<HookEvent, List<SessionHookMatcher>>? hooks})
    : hooks = hooks ?? {};
}

/// Derived hook matcher (without function hooks).
class SessionDerivedHookMatcher {
  final String matcher;
  final List<HookCommand> hooks;
  final String? skillRoot;

  const SessionDerivedHookMatcher({
    required this.matcher,
    required this.hooks,
    this.skillRoot,
  });
}

/// Session hooks state manager. Uses a Map for O(1) mutations
/// (same pattern as TS: Map not Record, to avoid O(N^2) copies).
class SessionHooksManager {
  final Map<String, SessionStore> _stores = {};

  /// Add a command or prompt hook to the session.
  void addSessionHook({
    required String sessionId,
    required HookEvent event,
    required String matcher,
    required HookCommand hook,
    void Function(HookCommand, AggregatedHookResult)? onHookSuccess,
    String? skillRoot,
  }) {
    _addHookToSession(
      sessionId: sessionId,
      event: event,
      matcher: matcher,
      hook: hook,
      onHookSuccess: onHookSuccess,
      skillRoot: skillRoot,
    );
  }

  /// Add a function hook to the session. Returns the hook ID.
  String addFunctionHook({
    required String sessionId,
    required HookEvent event,
    required String matcher,
    required Future<bool> Function(List<dynamic>, {Object? signal}) callback,
    required String errorMessage,
    int? timeout,
    String? id,
  }) {
    final hookId =
        id ??
        'function-hook-${DateTime.now().millisecondsSinceEpoch}-'
            '${(DateTime.now().microsecond / 1000).toStringAsFixed(3)}';
    final hook = FunctionHook(
      id: hookId,
      timeout: timeout ?? 5000,
      callback: callback,
      errorMessage: errorMessage,
    );
    _addHookToSession(
      sessionId: sessionId,
      event: event,
      matcher: matcher,
      hook: hook,
    );
    return hookId;
  }

  /// Remove a function hook by ID from the session.
  void removeFunctionHook({
    required String sessionId,
    required HookEvent event,
    required String hookId,
  }) {
    final store = _stores[sessionId];
    if (store == null) return;

    final eventMatchers = store.hooks[event] ?? [];
    final updatedMatchers = <SessionHookMatcher>[];
    for (final m in eventMatchers) {
      final updatedHooks = m.hooks.where((h) {
        if (h.hook is FunctionHook) {
          return (h.hook as FunctionHook).id != hookId;
        }
        return true;
      }).toList();
      if (updatedHooks.isNotEmpty) {
        updatedMatchers.add(
          SessionHookMatcher(
            matcher: m.matcher,
            skillRoot: m.skillRoot,
            hooks: updatedHooks,
          ),
        );
      }
    }

    if (updatedMatchers.isNotEmpty) {
      store.hooks[event] = updatedMatchers;
    } else {
      store.hooks.remove(event);
    }
  }

  /// Remove a specific hook from the session.
  void removeSessionHook({
    required String sessionId,
    required HookEvent event,
    required HookCommand hook,
  }) {
    final store = _stores[sessionId];
    if (store == null) return;

    final eventMatchers = store.hooks[event] ?? [];
    final updatedMatchers = <SessionHookMatcher>[];
    for (final m in eventMatchers) {
      final updatedHooks = m.hooks
          .where((h) => !isHookEqual(h.hook, hook))
          .toList();
      if (updatedHooks.isNotEmpty) {
        updatedMatchers.add(
          SessionHookMatcher(
            matcher: m.matcher,
            skillRoot: m.skillRoot,
            hooks: updatedHooks,
          ),
        );
      }
    }

    if (updatedMatchers.isNotEmpty) {
      store.hooks[event] = updatedMatchers;
    } else {
      store.hooks.remove(event);
    }
  }

  /// Get all session hooks for a specific event (excluding function hooks).
  Map<HookEvent, List<SessionDerivedHookMatcher>> getSessionHooks(
    String sessionId, {
    HookEvent? event,
  }) {
    final store = _stores[sessionId];
    if (store == null) return {};

    final result = <HookEvent, List<SessionDerivedHookMatcher>>{};

    List<SessionDerivedHookMatcher> convertMatchers(
      List<SessionHookMatcher> matchers,
    ) {
      return matchers.map((sm) {
        final nonFunctionHooks = sm.hooks
            .map((h) => h.hook)
            .where((h) => h is! FunctionHook)
            .toList();
        return SessionDerivedHookMatcher(
          matcher: sm.matcher,
          hooks: nonFunctionHooks,
          skillRoot: sm.skillRoot,
        );
      }).toList();
    }

    if (event != null) {
      final matchers = store.hooks[event];
      if (matchers != null) {
        result[event] = convertMatchers(matchers);
      }
    } else {
      for (final evt in hookEvents) {
        final matchers = store.hooks[evt];
        if (matchers != null) {
          result[evt] = convertMatchers(matchers);
        }
      }
    }

    return result;
  }

  /// Get all session function hooks for a specific event.
  Map<HookEvent, List<FunctionHookMatcher>> getSessionFunctionHooks(
    String sessionId, {
    HookEvent? event,
  }) {
    final store = _stores[sessionId];
    if (store == null) return {};

    final result = <HookEvent, List<FunctionHookMatcher>>{};

    List<FunctionHookMatcher> extractFunctionHooks(
      List<SessionHookMatcher> matchers,
    ) {
      return matchers
          .map((sm) {
            final funcHooks = sm.hooks
                .map((h) => h.hook)
                .whereType<FunctionHook>()
                .toList();
            return FunctionHookMatcher(matcher: sm.matcher, hooks: funcHooks);
          })
          .where((m) => m.hooks.isNotEmpty)
          .toList();
    }

    if (event != null) {
      final matchers = store.hooks[event];
      if (matchers != null) {
        final funcMatchers = extractFunctionHooks(matchers);
        if (funcMatchers.isNotEmpty) {
          result[event] = funcMatchers;
        }
      }
    } else {
      for (final evt in hookEvents) {
        final matchers = store.hooks[evt];
        if (matchers != null) {
          final funcMatchers = extractFunctionHooks(matchers);
          if (funcMatchers.isNotEmpty) {
            result[evt] = funcMatchers;
          }
        }
      }
    }

    return result;
  }

  /// Get callback info for a specific session hook.
  SessionHookEntry? getSessionHookCallback({
    required String sessionId,
    required HookEvent event,
    required String matcher,
    required HookCommand hook,
  }) {
    final store = _stores[sessionId];
    if (store == null) return null;

    final eventMatchers = store.hooks[event];
    if (eventMatchers == null) return null;

    for (final matcherEntry in eventMatchers) {
      if (matcherEntry.matcher == matcher || matcher.isEmpty) {
        for (final hookEntry in matcherEntry.hooks) {
          if (isHookEqual(hookEntry.hook, hook)) {
            return hookEntry;
          }
        }
      }
    }
    return null;
  }

  /// Clear all session hooks for a specific session.
  void clearSessionHooks(String sessionId) {
    _stores.remove(sessionId);
  }

  /// Internal: add a hook to the session store.
  void _addHookToSession({
    required String sessionId,
    required HookEvent event,
    required String matcher,
    required HookCommand hook,
    void Function(HookCommand, AggregatedHookResult)? onHookSuccess,
    String? skillRoot,
  }) {
    final store = _stores.putIfAbsent(sessionId, () => SessionStore());
    final eventMatchers = store.hooks[event] ?? [];

    final existingIdx = eventMatchers.indexWhere(
      (m) => m.matcher == matcher && m.skillRoot == skillRoot,
    );

    if (existingIdx >= 0) {
      eventMatchers[existingIdx].hooks.add(
        SessionHookEntry(hook: hook, onHookSuccess: onHookSuccess),
      );
    } else {
      eventMatchers.add(
        SessionHookMatcher(
          matcher: matcher,
          skillRoot: skillRoot,
          hooks: [SessionHookEntry(hook: hook, onHookSuccess: onHookSuccess)],
        ),
      );
    }

    store.hooks[event] = eventMatchers;
  }
}

/// Function hook matcher (for getSessionFunctionHooks).
class FunctionHookMatcher {
  final String matcher;
  final List<FunctionHook> hooks;

  const FunctionHookMatcher({required this.matcher, required this.hooks});
}

// ---------------------------------------------------------------------------
// Hook event metadata (from hooksConfigManager.ts)
// ---------------------------------------------------------------------------

/// Metadata for matching hook events.
class MatcherMetadata {
  final String fieldToMatch;
  final List<String> values;

  const MatcherMetadata({required this.fieldToMatch, required this.values});
}

/// Metadata for a hook event.
class HookEventMetadata {
  final String summary;
  final String description;
  final MatcherMetadata? matcherMetadata;

  const HookEventMetadata({
    required this.summary,
    required this.description,
    this.matcherMetadata,
  });
}

/// Get metadata for all hook events.
Map<HookEvent, HookEventMetadata> getHookEventMetadata(List<String> toolNames) {
  return {
    'PreToolUse': HookEventMetadata(
      summary: 'Before tool execution',
      description:
          'Input to command is JSON of tool call arguments.\n'
          'Exit code 0 - stdout/stderr not shown\n'
          'Exit code 2 - show stderr to model and block tool call\n'
          'Other exit codes - show stderr to user only but continue with tool call',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'tool_name',
        values: toolNames,
      ),
    ),
    'PostToolUse': HookEventMetadata(
      summary: 'After tool execution',
      description:
          'Input to command is JSON with fields "inputs" and "response".\n'
          'Exit code 0 - stdout shown in transcript mode\n'
          'Exit code 2 - show stderr to model immediately\n'
          'Other exit codes - show stderr to user only',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'tool_name',
        values: toolNames,
      ),
    ),
    'PostToolUseFailure': HookEventMetadata(
      summary: 'After tool execution fails',
      description:
          'Input to command is JSON with tool_name, tool_input, etc.\n'
          'Exit code 0 - stdout shown in transcript mode\n'
          'Exit code 2 - show stderr to model immediately',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'tool_name',
        values: toolNames,
      ),
    ),
    'PermissionDenied': HookEventMetadata(
      summary: 'After auto mode classifier denies a tool call',
      description:
          'Input to command is JSON with tool_name, tool_input, tool_use_id, and reason.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'tool_name',
        values: toolNames,
      ),
    ),
    'Notification': HookEventMetadata(
      summary: 'When notifications are sent',
      description:
          'Input to command is JSON with notification message and type.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'notification_type',
        values: [
          'permission_prompt',
          'idle_prompt',
          'auth_success',
          'elicitation_dialog',
          'elicitation_complete',
          'elicitation_response',
        ],
      ),
    ),
    'UserPromptSubmit': const HookEventMetadata(
      summary: 'When the user submits a prompt',
      description: 'Input to command is JSON with original user prompt text.',
    ),
    'SessionStart': HookEventMetadata(
      summary: 'When a new session is started',
      description: 'Input to command is JSON with session start source.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'source',
        values: ['startup', 'resume', 'clear', 'compact'],
      ),
    ),
    'Stop': const HookEventMetadata(
      summary: 'Right before Neomage concludes its response',
      description:
          'Exit code 0 - stdout/stderr not shown\n'
          'Exit code 2 - show stderr to model and continue conversation',
    ),
    'StopFailure': HookEventMetadata(
      summary: 'When the turn ends due to an API error',
      description: 'Fires instead of Stop when an API error ended the turn.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'error',
        values: [
          'rate_limit',
          'authentication_failed',
          'billing_error',
          'invalid_request',
          'server_error',
          'max_output_tokens',
          'unknown',
        ],
      ),
    ),
    'SubagentStart': const HookEventMetadata(
      summary: 'When a subagent is started',
      description: 'Input to command is JSON with agent_id and agent_type.',
      matcherMetadata: MatcherMetadata(fieldToMatch: 'agent_type', values: []),
    ),
    'SubagentStop': const HookEventMetadata(
      summary: 'Right before a subagent concludes its response',
      description: 'Input includes agent_id, agent_type, and transcript_path.',
      matcherMetadata: MatcherMetadata(fieldToMatch: 'agent_type', values: []),
    ),
    'PreCompact': HookEventMetadata(
      summary: 'Before conversation compaction',
      description: 'Input to command is JSON with compaction details.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'trigger',
        values: ['manual', 'auto'],
      ),
    ),
    'PostCompact': HookEventMetadata(
      summary: 'After conversation compaction',
      description: 'Input includes compaction details and the summary.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'trigger',
        values: ['manual', 'auto'],
      ),
    ),
    'SessionEnd': HookEventMetadata(
      summary: 'When a session is ending',
      description: 'Input to command is JSON with session end reason.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'reason',
        values: ['clear', 'logout', 'prompt_input_exit', 'other'],
      ),
    ),
    'PermissionRequest': HookEventMetadata(
      summary: 'When a permission dialog is displayed',
      description: 'Input includes tool_name, tool_input, and tool_use_id.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'tool_name',
        values: toolNames,
      ),
    ),
    'Setup': HookEventMetadata(
      summary: 'Repo setup hooks for init and maintenance',
      description:
          'Input to command is JSON with trigger (init or maintenance).',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'trigger',
        values: ['init', 'maintenance'],
      ),
    ),
    'TeammateIdle': const HookEventMetadata(
      summary: 'When a teammate is about to go idle',
      description: 'Input includes teammate_name and team_name.',
    ),
    'TaskCreated': const HookEventMetadata(
      summary: 'When a task is being created',
      description: 'Input includes task_id, task_subject, task_description.',
    ),
    'TaskCompleted': const HookEventMetadata(
      summary: 'When a task is being marked as completed',
      description: 'Input includes task_id, task_subject, task_description.',
    ),
    'Elicitation': const HookEventMetadata(
      summary: 'When an MCP server requests user input',
      description:
          'Input includes mcp_server_name, message, and requested_schema.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'mcp_server_name',
        values: [],
      ),
    ),
    'ElicitationResult': const HookEventMetadata(
      summary: 'After a user responds to an MCP elicitation',
      description: 'Input includes mcp_server_name, action, content.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'mcp_server_name',
        values: [],
      ),
    ),
    'ConfigChange': HookEventMetadata(
      summary: 'When configuration files change during a session',
      description: 'Input includes source and file_path.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'source',
        values: [
          'user_settings',
          'project_settings',
          'local_settings',
          'policy_settings',
          'skills',
        ],
      ),
    ),
    'InstructionsLoaded': HookEventMetadata(
      summary: 'When an instruction file is loaded',
      description: 'Input includes file_path, memory_type, load_reason.',
      matcherMetadata: MatcherMetadata(
        fieldToMatch: 'load_reason',
        values: [
          'session_start',
          'nested_traversal',
          'path_glob_match',
          'include',
          'compact',
        ],
      ),
    ),
    'WorktreeCreate': const HookEventMetadata(
      summary: 'Create an isolated worktree',
      description: 'Input is JSON with name (suggested worktree slug).',
    ),
    'WorktreeRemove': const HookEventMetadata(
      summary: 'Remove a previously created worktree',
      description: 'Input is JSON with worktree_path.',
    ),
    'CwdChanged': const HookEventMetadata(
      summary: 'After the working directory changes',
      description: 'Input is JSON with old_cwd and new_cwd.',
    ),
    'FileChanged': const HookEventMetadata(
      summary: 'When a watched file changes',
      description: 'Input is JSON with file_path and event.',
    ),
  };
}

// ---------------------------------------------------------------------------
// Hook event emission system (from hookEvents.ts)
// ---------------------------------------------------------------------------

/// Hook execution event types.
enum HookExecutionEventType { started, progress, response }

/// Base class for hook execution events.
abstract class HookExecutionEvent {
  HookExecutionEventType get type;
  String get hookId;
  String get hookName;
  String get hookEvent;
}

/// Emitted when a hook starts executing.
class HookStartedEvent implements HookExecutionEvent {
  @override
  final HookExecutionEventType type = HookExecutionEventType.started;
  @override
  final String hookId;
  @override
  final String hookName;
  @override
  final String hookEvent;

  const HookStartedEvent({
    required this.hookId,
    required this.hookName,
    required this.hookEvent,
  });
}

/// Emitted periodically during hook execution.
class HookProgressEvent implements HookExecutionEvent {
  @override
  final HookExecutionEventType type = HookExecutionEventType.progress;
  @override
  final String hookId;
  @override
  final String hookName;
  @override
  final String hookEvent;
  final String stdout;
  final String stderr;
  final String output;

  const HookProgressEvent({
    required this.hookId,
    required this.hookName,
    required this.hookEvent,
    required this.stdout,
    required this.stderr,
    required this.output,
  });
}

/// Emitted when a hook finishes executing.
class HookResponseEvent implements HookExecutionEvent {
  @override
  final HookExecutionEventType type = HookExecutionEventType.response;
  @override
  final String hookId;
  @override
  final String hookName;
  @override
  final String hookEvent;
  final String output;
  final String stdout;
  final String stderr;
  final int? exitCode;
  final String outcome; // 'success' | 'error' | 'cancelled'

  const HookResponseEvent({
    required this.hookId,
    required this.hookName,
    required this.hookEvent,
    required this.output,
    required this.stdout,
    required this.stderr,
    this.exitCode,
    required this.outcome,
  });
}

typedef HookEventHandler = void Function(HookExecutionEvent event);

/// Hook events always emitted regardless of includeHookEvents option.
const List<String> alwaysEmittedHookEvents = ['SessionStart', 'Setup'];

const int _maxPendingEvents = 100;

/// Hook event emission manager.
class HookEventEmitter {
  final List<HookExecutionEvent> _pendingEvents = [];
  HookEventHandler? _handler;
  bool _allHookEventsEnabled = false;

  void registerHandler(HookEventHandler? handler) {
    _handler = handler;
    if (handler != null && _pendingEvents.isNotEmpty) {
      for (final event in _pendingEvents) {
        handler(event);
      }
      _pendingEvents.clear();
    }
  }

  void _emit(HookExecutionEvent event) {
    if (_handler != null) {
      _handler!(event);
    } else {
      _pendingEvents.add(event);
      if (_pendingEvents.length > _maxPendingEvents) {
        _pendingEvents.removeAt(0);
      }
    }
  }

  bool _shouldEmit(String hookEvent) {
    if (alwaysEmittedHookEvents.contains(hookEvent)) return true;
    return _allHookEventsEnabled && hookEvents.contains(hookEvent);
  }

  void emitHookStarted(String hookId, String hookName, String hookEvent) {
    if (!_shouldEmit(hookEvent)) return;
    _emit(
      HookStartedEvent(
        hookId: hookId,
        hookName: hookName,
        hookEvent: hookEvent,
      ),
    );
  }

  void emitHookProgress({
    required String hookId,
    required String hookName,
    required String hookEvent,
    required String stdout,
    required String stderr,
    required String output,
  }) {
    if (!_shouldEmit(hookEvent)) return;
    _emit(
      HookProgressEvent(
        hookId: hookId,
        hookName: hookName,
        hookEvent: hookEvent,
        stdout: stdout,
        stderr: stderr,
        output: output,
      ),
    );
  }

  void emitHookResponse({
    required String hookId,
    required String hookName,
    required String hookEvent,
    required String output,
    required String stdout,
    required String stderr,
    int? exitCode,
    required String outcome,
  }) {
    if (!_shouldEmit(hookEvent)) return;
    _emit(
      HookResponseEvent(
        hookId: hookId,
        hookName: hookName,
        hookEvent: hookEvent,
        output: output,
        stdout: stdout,
        stderr: stderr,
        exitCode: exitCode,
        outcome: outcome,
      ),
    );
  }

  void setAllHookEventsEnabled(bool enabled) {
    _allHookEventsEnabled = enabled;
  }

  void clear() {
    _handler = null;
    _pendingEvents.clear();
    _allHookEventsEnabled = false;
  }
}

// ---------------------------------------------------------------------------
// SSRF Guard (from ssrfGuard.ts)
// ---------------------------------------------------------------------------

/// Returns true if the address is in a range that HTTP hooks should not reach.
/// Loopback (127.0.0.0/8, ::1) is intentionally ALLOWED for local dev hooks.
bool isBlockedAddress(String address) {
  // Simple IPv4 check
  final v4Parts = address.split('.');
  if (v4Parts.length == 4) {
    final nums = v4Parts.map(int.tryParse).toList();
    if (nums.every((n) => n != null)) {
      return _isBlockedV4(nums.cast<int>());
    }
  }

  // IPv6 check
  final lower = address.toLowerCase();
  if (lower == '::1') return false; // loopback allowed
  if (lower == '::') return true; // unspecified

  // fc00::/7 unique local
  if (lower.startsWith('fc') || lower.startsWith('fd')) return true;

  // fe80::/10 link-local
  final firstHextet = lower.split(':').first;
  if (firstHextet.length == 4) {
    final val = int.tryParse(firstHextet, radix: 16);
    if (val != null && val >= 0xfe80 && val <= 0xfebf) return true;
  }

  return false;
}

bool _isBlockedV4(List<int> parts) {
  final a = parts[0];
  final b = parts[1];

  // Loopback explicitly allowed
  if (a == 127) return false;

  // 0.0.0.0/8
  if (a == 0) return true;
  // 10.0.0.0/8
  if (a == 10) return true;
  // 169.254.0.0/16 link-local (cloud metadata)
  if (a == 169 && b == 254) return true;
  // 172.16.0.0/12
  if (a == 172 && b >= 16 && b <= 31) return true;
  // 100.64.0.0/10 shared address space
  if (a == 100 && b >= 64 && b <= 127) return true;
  // 192.168.0.0/16
  if (a == 192 && b == 168) return true;

  return false;
}

// ---------------------------------------------------------------------------
// Async Hook Registry (from AsyncHookRegistry.ts)
// ---------------------------------------------------------------------------

/// A pending async hook awaiting completion.
class PendingAsyncHook {
  final String processId;
  final String hookId;
  final String hookName;
  final String hookEvent;
  final String? toolName;
  final String? pluginId;
  final DateTime startTime;
  final int timeout;
  final String command;
  bool responseAttachmentSent;

  PendingAsyncHook({
    required this.processId,
    required this.hookId,
    required this.hookName,
    required this.hookEvent,
    this.toolName,
    this.pluginId,
    required this.startTime,
    required this.timeout,
    required this.command,
    this.responseAttachmentSent = false,
  });
}

/// Registry for tracking async hooks awaiting completion.
class AsyncHookRegistry {
  final Map<String, PendingAsyncHook> _pendingHooks = {};

  void register(PendingAsyncHook hook) {
    _pendingHooks[hook.processId] = hook;
  }

  List<PendingAsyncHook> getPending() {
    return _pendingHooks.values
        .where((h) => !h.responseAttachmentSent)
        .toList();
  }

  void removeDelivered(List<String> processIds) {
    for (final id in processIds) {
      final hook = _pendingHooks[id];
      if (hook != null && hook.responseAttachmentSent) {
        _pendingHooks.remove(id);
      }
    }
  }

  void clear() {
    _pendingHooks.clear();
  }

  int get count => _pendingHooks.length;
}
