// Extended session management — port of neomage sessionRestore.ts +
// sessionStart.ts + sessionState.ts + sessionEnvironment.ts +
// sessionActivity.ts + sessionTitle.ts + sessionFileAccessHooks.ts +
// sessionIngressAuth.ts.
// Session restore, start hooks, state notifications, environment scripts,
// activity heartbeat, title generation, file access hooks, and ingress auth.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════
// Part 1 — Session State (from sessionState.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Session state enumeration.
enum SessionState { idle, running, requiresAction }

/// Context carried with requires_action transitions.
class RequiresActionDetails {
  RequiresActionDetails({
    required this.toolName,
    required this.actionDescription,
    required this.toolUseId,
    required this.requestId,
    this.input,
  });

  final String toolName;

  /// Human-readable summary, e.g. "Editing src/foo.ts".
  final String actionDescription;
  final String toolUseId;
  final String requestId;

  /// Raw tool input — frontend reads from external_metadata.pending_action.input.
  final Map<String, dynamic>? input;

  Map<String, dynamic> toJson() => {
    'tool_name': toolName,
    'action_description': actionDescription,
    'tool_use_id': toolUseId,
    'request_id': requestId,
    if (input != null) 'input': input,
  };
}

/// External metadata keys for CCR push / GetSession.
class SessionExternalMetadata {
  SessionExternalMetadata({
    this.permissionMode,
    this.isUltraplanMode,
    this.model,
    this.pendingAction,
    this.postTurnSummary,
    this.taskSummary,
  });

  final String? permissionMode;
  final bool? isUltraplanMode;
  final String? model;
  final RequiresActionDetails? pendingAction;
  final Object? postTurnSummary;
  final String? taskSummary;
}

/// Listener types.
typedef SessionStateChangedListener =
    void Function(SessionState state, RequiresActionDetails? details);
typedef SessionMetadataChangedListener =
    void Function(SessionExternalMetadata metadata);
typedef PermissionModeChangedListener = void Function(String mode);

SessionStateChangedListener? _stateListener;
SessionMetadataChangedListener? _metadataListener;
PermissionModeChangedListener? _permissionModeListener;

/// Register the session-state-change listener.
void setSessionStateChangedListener(SessionStateChangedListener? cb) {
  _stateListener = cb;
}

/// Register the session-metadata-change listener.
void setSessionMetadataChangedListener(SessionMetadataChangedListener? cb) {
  _metadataListener = cb;
}

/// Register the permission-mode-change listener.
void setPermissionModeChangedListener(PermissionModeChangedListener? cb) {
  _permissionModeListener = cb;
}

bool _hasPendingAction = false;
SessionState _currentState = SessionState.idle;

/// Get the current session state.
SessionState getSessionState() => _currentState;

/// Notify listeners that session state changed.
void notifySessionStateChanged(
  SessionState state, {
  RequiresActionDetails? details,
}) {
  _currentState = state;
  _stateListener?.call(state, details);

  if (state == SessionState.requiresAction && details != null) {
    _hasPendingAction = true;
    _metadataListener?.call(SessionExternalMetadata(pendingAction: details));
  } else if (_hasPendingAction) {
    _hasPendingAction = false;
    _metadataListener?.call(SessionExternalMetadata(pendingAction: null));
  }

  if (state == SessionState.idle) {
    _metadataListener?.call(SessionExternalMetadata(taskSummary: null));
  }
}

/// Notify listeners that session metadata changed.
void notifySessionMetadataChanged(SessionExternalMetadata metadata) {
  _metadataListener?.call(metadata);
}

/// Fired by onChangeAppState when toolPermissionContext.mode changes.
void notifyPermissionModeChanged(String mode) {
  _permissionModeListener?.call(mode);
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 2 — Session Activity (from sessionActivity.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Activity heartbeat interval.
const Duration _sessionActivityInterval = Duration(seconds: 30);

/// Why activity started.
enum SessionActivityReason { apiCall, toolExec }

void Function()? _activityCallback;
int _activityRefcount = 0;
final Map<SessionActivityReason, int> _activeReasons = {};
Timer? _heartbeatTimer;
Timer? _idleTimer;

void _startHeartbeatTimer() {
  _clearIdleTimer();
  _heartbeatTimer = Timer.periodic(_sessionActivityInterval, (_) {
    final shouldSend = _isEnvTruthy(
      Platform.environment['MAGE_REMOTE_SEND_KEEPALIVES'],
    );
    if (shouldSend) {
      _activityCallback?.call();
    }
  });
}

void _startIdleTimer() {
  _clearIdleTimer();
  if (_activityCallback == null) return;
  _idleTimer = Timer(_sessionActivityInterval, () {
    _idleTimer = null;
  });
}

void _clearIdleTimer() {
  _idleTimer?.cancel();
  _idleTimer = null;
}

/// Register the keep-alive sender.
void registerSessionActivityCallback(void Function() cb) {
  _activityCallback = cb;
  if (_activityRefcount > 0 && _heartbeatTimer == null) {
    _startHeartbeatTimer();
  }
}

/// Unregister the keep-alive sender.
void unregisterSessionActivityCallback() {
  _activityCallback = null;
  _heartbeatTimer?.cancel();
  _heartbeatTimer = null;
  _clearIdleTimer();
}

/// Send a single keep-alive signal.
void sendSessionActivitySignal() {
  final shouldSend = _isEnvTruthy(
    Platform.environment['MAGE_REMOTE_SEND_KEEPALIVES'],
  );
  if (shouldSend) {
    _activityCallback?.call();
  }
}

/// Check if session activity tracking is active.
bool isSessionActivityTrackingActive() => _activityCallback != null;

/// Increment the activity refcount. When transitioning 0->1, start heartbeat.
void startSessionActivity(SessionActivityReason reason) {
  _activityRefcount++;
  _activeReasons[reason] = (_activeReasons[reason] ?? 0) + 1;
  if (_activityRefcount == 1) {
    if (_activityCallback != null && _heartbeatTimer == null) {
      _startHeartbeatTimer();
    }
  }
}

/// Decrement the activity refcount. When reaching 0, stop heartbeat and
/// start idle timer.
void stopSessionActivity(SessionActivityReason reason) {
  if (_activityRefcount > 0) _activityRefcount--;
  final n = (_activeReasons[reason] ?? 0) - 1;
  if (n > 0) {
    _activeReasons[reason] = n;
  } else {
    _activeReasons.remove(reason);
  }
  if (_activityRefcount == 0 && _heartbeatTimer != null) {
    _heartbeatTimer!.cancel();
    _heartbeatTimer = null;
    _startIdleTimer();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 3 — Session Title (from sessionTitle.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Maximum conversation text passed to the title generator.
const int _maxConversationText = 1000;

/// The system prompt used for generating session titles.
const String _sessionTitlePrompt = '''
Generate a concise, sentence-case title (3-7 words) that captures the main topic or goal of this coding session. The title should be clear enough that the user recognizes the session in a list. Use sentence case: capitalize only the first word and proper nouns.

Return JSON with a single "title" field.

Good examples:
{"title": "Fix login button on mobile"}
{"title": "Add OAuth authentication"}
{"title": "Debug failing CI tests"}
{"title": "Refactor API client error handling"}

Bad (too vague): {"title": "Code changes"}
Bad (too long): {"title": "Investigate and fix the issue where the login button does not respond on mobile devices"}
Bad (wrong case): {"title": "Fix Login Button On Mobile"}''';

/// Flatten a message array into a single text string for Haiku title input.
String extractConversationText(List<Map<String, dynamic>> messages) {
  final parts = <String>[];
  for (final msg in messages) {
    final type = msg['type'] as String?;
    if (type != 'user' && type != 'assistant') continue;
    if (msg['isMeta'] == true) continue;
    final origin = msg['origin'] as Map<String, dynamic>?;
    if (origin != null && origin['kind'] != 'human') continue;

    final content = msg['message']?['content'];
    if (content is String) {
      parts.add(content);
    } else if (content is List) {
      for (final block in content) {
        if (block is Map<String, dynamic> &&
            block['type'] == 'text' &&
            block['text'] is String) {
          parts.add(block['text'] as String);
        }
      }
    }
  }
  final text = parts.join('\n');
  return text.length > _maxConversationText
      ? text.substring(text.length - _maxConversationText)
      : text;
}

/// Callback type for querying the Haiku model.
typedef QueryHaikuFn =
    Future<String?> Function({
      required String systemPrompt,
      required String userPrompt,
    });

/// Global Haiku query callback (set by the app).
QueryHaikuFn? _queryHaiku;

/// Set the Haiku query callback.
void setQueryHaiku(QueryHaikuFn fn) {
  _queryHaiku = fn;
}

/// Generate a sentence-case session title from a description or first message.
/// Returns `null` on error or if Haiku returns unparseable output.
Future<String?> generateSessionTitle(String description) async {
  final trimmed = description.trim();
  if (trimmed.isEmpty) return null;

  if (_queryHaiku == null) return null;

  try {
    final result = await _queryHaiku!(
      systemPrompt: _sessionTitlePrompt,
      userPrompt: trimmed,
    );
    if (result == null) return null;
    final parsed = jsonDecode(result) as Map<String, dynamic>?;
    final title = (parsed?['title'] as String?)?.trim();
    return (title != null && title.isNotEmpty) ? title : null;
  } catch (_) {
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 4 — Session Environment (from sessionEnvironment.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Cache for the session environment script.
/// `null` means "checked disk, no files exist".
String? _sessionEnvScript;
bool _sessionEnvScriptChecked = false;

/// Get the session env directory path.
Future<String> getSessionEnvDirPath(String sessionId) async {
  final dir = p.join(_getNeomageConfigHomeDir(), 'session-env', sessionId);
  await Directory(dir).create(recursive: true);
  return dir;
}

/// Get hook env file path.
Future<String> getHookEnvFilePath(
  String sessionId,
  String hookEvent,
  int hookIndex,
) async {
  final prefix = hookEvent.toLowerCase();
  final dir = await getSessionEnvDirPath(sessionId);
  return p.join(dir, '$prefix-hook-$hookIndex.sh');
}

/// Clear CWD-related env files.
Future<void> clearCwdEnvFiles(String sessionId) async {
  try {
    final dir = await getSessionEnvDirPath(sessionId);
    final files = await Directory(dir).list().toList();
    await Future.wait(
      files
          .whereType<File>()
          .where((f) {
            final name = p.basename(f.path);
            return (name.startsWith('filechanged-hook-') ||
                    name.startsWith('cwdchanged-hook-')) &&
                _hookEnvRegex.hasMatch(name);
          })
          .map((f) => f.writeAsString('')),
    );
  } catch (_) {}
}

/// Invalidate the session environment cache.
void invalidateSessionEnvCache() {
  _sessionEnvScript = null;
  _sessionEnvScriptChecked = false;
}

/// Hook env file matching regex.
final RegExp _hookEnvRegex = RegExp(
  r'^(setup|sessionstart|cwdchanged|filechanged)-hook-(\d+)\.sh$',
);

/// Hook event priority for sorting.
const Map<String, int> _hookEnvPriority = {
  'setup': 0,
  'sessionstart': 1,
  'cwdchanged': 2,
  'filechanged': 3,
};

/// Sort hook env files by event type then by index.
int _sortHookEnvFiles(String a, String b) {
  final aMatch = _hookEnvRegex.firstMatch(a);
  final bMatch = _hookEnvRegex.firstMatch(b);
  final aType = aMatch?.group(1) ?? '';
  final bType = bMatch?.group(1) ?? '';
  if (aType != bType) {
    return (_hookEnvPriority[aType] ?? 99) - (_hookEnvPriority[bType] ?? 99);
  }
  final aIndex = int.tryParse(aMatch?.group(2) ?? '0') ?? 0;
  final bIndex = int.tryParse(bMatch?.group(2) ?? '0') ?? 0;
  return aIndex - bIndex;
}

/// Get the session environment script (sourced before shell commands).
Future<String?> getSessionEnvironmentScript(String sessionId) async {
  if (Platform.isWindows) return null;

  if (_sessionEnvScriptChecked) return _sessionEnvScript;

  final scripts = <String>[];

  // Check for MAGE_ENV_FILE.
  final envFile = Platform.environment['MAGE_ENV_FILE'];
  if (envFile != null) {
    try {
      final envScript = (await File(envFile).readAsString()).trim();
      if (envScript.isNotEmpty) {
        scripts.add(envScript);
      }
    } catch (_) {}
  }

  // Load hook environment files from session directory.
  final sessionEnvDir = await getSessionEnvDirPath(sessionId);
  try {
    final files = await Directory(sessionEnvDir).list().toList();
    final hookFiles =
        files
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((name) => _hookEnvRegex.hasMatch(name))
            .toList()
          ..sort(_sortHookEnvFiles);

    for (final file in hookFiles) {
      final filePath = p.join(sessionEnvDir, file);
      try {
        final content = (await File(filePath).readAsString()).trim();
        if (content.isNotEmpty) {
          scripts.add(content);
        }
      } catch (_) {}
    }
  } catch (_) {}

  _sessionEnvScriptChecked = true;
  if (scripts.isEmpty) {
    _sessionEnvScript = null;
    return null;
  }

  _sessionEnvScript = scripts.join('\n');
  return _sessionEnvScript;
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 5 — Session Start Hooks (from sessionStart.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Hook result message from session start/setup hooks.
class HookResultMessage {
  HookResultMessage({
    this.content,
    this.hookName,
    this.toolUseId,
    this.hookEvent,
    this.additionalContexts,
    this.initialUserMessage,
    this.watchPaths,
  });

  final String? content;
  final String? hookName;
  final String? toolUseId;
  final String? hookEvent;
  final List<String>? additionalContexts;
  final String? initialUserMessage;
  final List<String>? watchPaths;
}

/// Options for processing session start hooks.
class SessionStartHooksOptions {
  SessionStartHooksOptions({
    this.sessionId,
    this.agentType,
    this.model,
    this.forceSyncExecution,
  });

  final String? sessionId;
  final String? agentType;
  final String? model;
  final bool? forceSyncExecution;
}

/// Pending initial user message side-channel.
String? _pendingInitialUserMessage;

/// Take the pending initial user message (consumed once).
String? takeInitialUserMessage() {
  final v = _pendingInitialUserMessage;
  _pendingInitialUserMessage = null;
  return v;
}

/// Callback types for hook execution.
typedef ExecuteSessionStartHooksFn =
    Stream<HookResultMessage> Function(
      String source,
      SessionStartHooksOptions options,
    );
typedef ExecuteSetupHooksFn =
    Stream<HookResultMessage> Function(
      String trigger, {
      bool? forceSyncExecution,
    });
typedef LoadPluginHooksFn = Future<void> Function();
typedef IsBareModeFn = bool Function();

/// Global hook execution callbacks.
ExecuteSessionStartHooksFn? _executeSessionStartHooks;
ExecuteSetupHooksFn? _executeSetupHooks;
LoadPluginHooksFn? _loadPluginHooks;
IsBareModeFn _isBareMode = () => false;

/// Set the session-start hooks executor.
void setExecuteSessionStartHooks(ExecuteSessionStartHooksFn fn) {
  _executeSessionStartHooks = fn;
}

/// Set the setup hooks executor.
void setExecuteSetupHooks(ExecuteSetupHooksFn fn) {
  _executeSetupHooks = fn;
}

/// Set the plugin hooks loader.
void setLoadPluginHooks(LoadPluginHooksFn fn) {
  _loadPluginHooks = fn;
}

/// Set the bare mode checker.
void setIsBareMode(IsBareModeFn fn) {
  _isBareMode = fn;
}

/// Process session start hooks.
Future<List<HookResultMessage>> processSessionStartHooks(
  String source, {
  SessionStartHooksOptions? options,
}) async {
  if (_isBareMode()) return [];

  final opts = options ?? SessionStartHooksOptions();
  final hookMessages = <HookResultMessage>[];
  final additionalContexts = <String>[];
  final allWatchPaths = <String>[];

  // Load plugin hooks.
  if (_loadPluginHooks != null) {
    try {
      await _loadPluginHooks!();
    } catch (e) {
      // Log error but don't crash.
    }
  }

  // Execute session start hooks.
  if (_executeSessionStartHooks != null) {
    await for (final hookResult in _executeSessionStartHooks!(source, opts)) {
      if (hookResult.content != null) {
        hookMessages.add(hookResult);
      }
      if (hookResult.additionalContexts != null &&
          hookResult.additionalContexts!.isNotEmpty) {
        additionalContexts.addAll(hookResult.additionalContexts!);
      }
      if (hookResult.initialUserMessage != null) {
        _pendingInitialUserMessage = hookResult.initialUserMessage;
      }
      if (hookResult.watchPaths != null && hookResult.watchPaths!.isNotEmpty) {
        allWatchPaths.addAll(hookResult.watchPaths!);
      }
    }
  }

  // If hooks provided additional context, add it as a message.
  if (additionalContexts.isNotEmpty) {
    hookMessages.add(
      HookResultMessage(
        content: additionalContexts.join('\n'),
        hookName: 'SessionStart',
        toolUseId: 'SessionStart',
        hookEvent: 'SessionStart',
      ),
    );
  }

  return hookMessages;
}

/// Process setup hooks.
Future<List<HookResultMessage>> processSetupHooks(
  String trigger, {
  bool? forceSyncExecution,
}) async {
  if (_isBareMode()) return [];

  final hookMessages = <HookResultMessage>[];
  final additionalContexts = <String>[];

  if (_loadPluginHooks != null) {
    try {
      await _loadPluginHooks!();
    } catch (_) {}
  }

  if (_executeSetupHooks != null) {
    await for (final hookResult in _executeSetupHooks!(
      trigger,
      forceSyncExecution: forceSyncExecution,
    )) {
      if (hookResult.content != null) {
        hookMessages.add(hookResult);
      }
      if (hookResult.additionalContexts != null &&
          hookResult.additionalContexts!.isNotEmpty) {
        additionalContexts.addAll(hookResult.additionalContexts!);
      }
    }
  }

  if (additionalContexts.isNotEmpty) {
    hookMessages.add(
      HookResultMessage(
        content: additionalContexts.join('\n'),
        hookName: 'Setup',
        toolUseId: 'Setup',
        hookEvent: 'Setup',
      ),
    );
  }

  return hookMessages;
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 6 — Session Restore (from sessionRestore.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Result of loading a conversation for resume.
class ResumeLoadResult {
  ResumeLoadResult({
    required this.messages,
    this.fileHistorySnapshots,
    this.attributionSnapshots,
    this.contentReplacements,
    this.contextCollapseCommits,
    this.contextCollapseSnapshot,
    this.sessionId,
    this.agentName,
    this.agentColor,
    this.agentSetting,
    this.customTitle,
    this.tag,
    this.mode,
    this.worktreeSession,
    this.prNumber,
    this.prUrl,
    this.prRepository,
  });

  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>>? fileHistorySnapshots;
  final List<Map<String, dynamic>>? attributionSnapshots;
  final List<Map<String, dynamic>>? contentReplacements;
  final List<Map<String, dynamic>>? contextCollapseCommits;
  final Map<String, dynamic>? contextCollapseSnapshot;
  final String? sessionId;
  final String? agentName;
  final String? agentColor;
  final String? agentSetting;
  final String? customTitle;
  final String? tag;
  final String? mode; // 'coordinator' | 'normal'
  final Map<String, dynamic>? worktreeSession;
  final int? prNumber;
  final String? prUrl;
  final String? prRepository;
}

/// Result of processing a resumed conversation for rendering.
class ProcessedResume {
  ProcessedResume({
    required this.messages,
    this.fileHistorySnapshots,
    this.contentReplacements,
    this.agentName,
    this.agentColor,
    this.restoredAgentDef,
    required this.initialState,
  });

  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>>? fileHistorySnapshots;
  final List<Map<String, dynamic>>? contentReplacements;
  final String? agentName;
  final String? agentColor;
  final Map<String, dynamic>? restoredAgentDef;
  final Map<String, dynamic> initialState;
}

/// Scan transcript for the last TodoWrite tool_use block and return its todos.
List<Map<String, dynamic>> extractTodosFromTranscript(
  List<Map<String, dynamic>> messages,
) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final msg = messages[i];
    if (msg['type'] != 'assistant') continue;
    final content = msg['message']?['content'];
    if (content is! List) continue;

    for (final block in content) {
      if (block is Map<String, dynamic> &&
          block['type'] == 'tool_use' &&
          block['name'] == 'TodoWrite') {
        final input = block['input'];
        if (input is Map<String, dynamic>) {
          final todos = input['todos'];
          if (todos is List) {
            return todos.cast<Map<String, dynamic>>();
          }
        }
        return [];
      }
    }
  }
  return [];
}

/// Restore session state (file history, attribution, todos) from log.
void restoreSessionStateFromLog(
  ResumeLoadResult result,
  void Function(void Function(Map<String, dynamic>)) setAppState,
) {
  // Restore file history state.
  if (result.fileHistorySnapshots != null &&
      result.fileHistorySnapshots!.isNotEmpty) {
    setAppState((prev) {
      prev['fileHistory'] = result.fileHistorySnapshots;
    });
  }

  // Restore attribution state.
  if (result.attributionSnapshots != null &&
      result.attributionSnapshots!.isNotEmpty) {
    setAppState((prev) {
      prev['attribution'] = result.attributionSnapshots;
    });
  }

  // Restore TodoWrite state from transcript.
  if (result.messages.isNotEmpty) {
    final todos = extractTodosFromTranscript(result.messages);
    if (todos.isNotEmpty) {
      setAppState((prev) {
        final todosMap = (prev['todos'] as Map<String, dynamic>?) ?? {};
        todosMap['default'] = todos;
        prev['todos'] = todosMap;
      });
    }
  }
}

/// Compute standalone agent context for session resume.
Map<String, dynamic>? computeStandaloneAgentContext(
  String? agentName,
  String? agentColor,
) {
  if (agentName == null && agentColor == null) return null;
  return {
    'name': agentName ?? '',
    'color': (agentColor == 'default') ? null : agentColor,
  };
}

/// Restore worktree working directory on resume.
void restoreWorktreeForResume(
  Map<String, dynamic>? worktreeSession, {
  void Function(String)? setCwd,
  void Function(String)? setOriginalCwd,
  void Function(Map<String, dynamic>?)? saveWorktreeState,
  Map<String, dynamic>? Function()? getCurrentWorktreeSession,
  void Function(Map<String, dynamic>?)? restoreWorktreeSession,
  void Function()? clearCaches,
}) {
  // If --worktree already created a fresh worktree, it takes precedence.
  final fresh = getCurrentWorktreeSession?.call();
  if (fresh != null) {
    saveWorktreeState?.call(fresh);
    return;
  }

  if (worktreeSession == null) return;

  final worktreePath = worktreeSession['worktreePath'] as String?;
  if (worktreePath == null) return;

  try {
    Directory.current = worktreePath;
  } catch (_) {
    // Directory is gone.
    saveWorktreeState?.call(null);
    return;
  }

  setCwd?.call(worktreePath);
  setOriginalCwd?.call(Directory.current.path);
  restoreWorktreeSession?.call(worktreeSession);
  clearCaches?.call();
}

/// Undo restoreWorktreeForResume before a mid-session /resume switches to
/// another session.
void exitRestoredWorktree({
  Map<String, dynamic>? Function()? getCurrentWorktreeSession,
  void Function(Map<String, dynamic>?)? restoreWorktreeSession,
  void Function(String)? setCwd,
  void Function(String)? setOriginalCwd,
  void Function()? clearCaches,
}) {
  final current = getCurrentWorktreeSession?.call();
  if (current == null) return;

  restoreWorktreeSession?.call(null);
  clearCaches?.call();

  final originalCwd = current['originalCwd'] as String?;
  if (originalCwd == null) return;

  try {
    Directory.current = originalCwd;
  } catch (_) {
    return;
  }
  setCwd?.call(originalCwd);
  setOriginalCwd?.call(Directory.current.path);
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 7 — Session File Access Hooks (from sessionFileAccessHooks.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Detect session file type from a path.
String? detectSessionFileType(String filePath) {
  if (filePath.contains('.neomage/') && filePath.endsWith('.md')) {
    return 'session_memory';
  }
  if (filePath.endsWith('.jsonl') && filePath.contains('projects/')) {
    return 'session_transcript';
  }
  return null;
}

/// Detect session pattern type from a glob pattern.
String? detectSessionPatternType(String pattern) {
  if (pattern.contains('.neomage/') && pattern.contains('.md')) {
    return 'session_memory';
  }
  if (pattern.contains('.jsonl') && pattern.contains('projects/')) {
    return 'session_transcript';
  }
  return null;
}

/// Check if a file path is an auto memory file.
bool isAutoMemFile(String filePath) {
  return filePath.contains('.neomage/') &&
      (filePath.endsWith('.md') || filePath.contains('/memory/'));
}

/// Get the file path from a tool input.
String? getFilePathFromInput(String toolName, Map<String, dynamic>? toolInput) {
  if (toolInput == null) return null;
  switch (toolName) {
    case 'FileRead':
    case 'FileEdit':
    case 'FileWrite':
      return toolInput['file_path'] as String?;
    default:
      return null;
  }
}

/// Get session file type from tool input.
String? getSessionFileTypeFromInput(
  String toolName,
  Map<String, dynamic>? toolInput,
) {
  if (toolInput == null) return null;
  switch (toolName) {
    case 'FileRead':
      final path = toolInput['file_path'] as String?;
      if (path == null) return null;
      return detectSessionFileType(path);
    case 'Grep':
      final grepPath = toolInput['path'] as String?;
      if (grepPath != null) {
        final pathType = detectSessionFileType(grepPath);
        if (pathType != null) return pathType;
      }
      final glob = toolInput['glob'] as String?;
      if (glob != null) {
        final globType = detectSessionPatternType(glob);
        if (globType != null) return globType;
      }
      return null;
    case 'Glob':
      final globPath = toolInput['path'] as String?;
      if (globPath != null) {
        final pathType = detectSessionFileType(globPath);
        if (pathType != null) return pathType;
      }
      final pattern = toolInput['pattern'] as String?;
      if (pattern != null) return detectSessionPatternType(pattern);
      return null;
    default:
      return null;
  }
}

/// Check if a tool use constitutes a memory file access.
bool isMemoryFileAccess(String toolName, Map<String, dynamic>? toolInput) {
  if (getSessionFileTypeFromInput(toolName, toolInput) == 'session_memory') {
    return true;
  }
  final filePath = getFilePathFromInput(toolName, toolInput);
  if (filePath != null && isAutoMemFile(filePath)) return true;
  return false;
}

/// Callback type for file-access hook registration.
typedef RegisterHookCallbacksFn =
    void Function(Map<String, List<Map<String, dynamic>>> callbacks);

/// Register session file access tracking hooks.
void registerSessionFileAccessHooks({
  required RegisterHookCallbacksFn registerHookCallbacks,
  void Function(String event, Map<String, dynamic>? props)? logEvent,
}) {
  void handleSessionFileAccess(
    String toolName,
    Map<String, dynamic>? toolInput,
  ) {
    final fileType = getSessionFileTypeFromInput(toolName, toolInput);

    if (fileType == 'session_memory') {
      logEvent?.call('session_memory_accessed', null);
    } else if (fileType == 'session_transcript') {
      logEvent?.call('transcript_accessed', null);
    }

    final filePath = getFilePathFromInput(toolName, toolInput);
    if (filePath != null && isAutoMemFile(filePath)) {
      logEvent?.call('memdir_accessed', {'tool': toolName});
    }
  }

  // The actual hook registration is delegated to the caller.
  // In the Dart port, this is a callback-based pattern.
  final hook = <String, dynamic>{
    'type': 'callback',
    'callback': handleSessionFileAccess,
    'timeout': 1,
    'internal': true,
  };

  registerHookCallbacks({
    'PostToolUse': [
      {
        'matcher': 'FileRead',
        'hooks': [hook],
      },
      {
        'matcher': 'Grep',
        'hooks': [hook],
      },
      {
        'matcher': 'Glob',
        'hooks': [hook],
      },
      {
        'matcher': 'FileEdit',
        'hooks': [hook],
      },
      {
        'matcher': 'FileWrite',
        'hooks': [hook],
      },
    ],
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 8 — Session Ingress Auth (from sessionIngressAuth.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Cached session ingress token.
String? _cachedSessionIngressToken;
bool _sessionIngressTokenChecked = false;

/// Well-known token file path for CCR.
const String _ccrSessionIngressTokenPath =
    '/home/claude/.neomage/remote/.session_ingress_token';

/// Read token from a well-known file path.
String? _readTokenFromWellKnownFile(String path) {
  try {
    final content = File(path).readAsStringSync().trim();
    return content.isNotEmpty ? content : null;
  } catch (_) {
    return null;
  }
}

/// Get token from file descriptor (legacy path).
String? _getTokenFromFileDescriptor() {
  if (_sessionIngressTokenChecked) return _cachedSessionIngressToken;

  final fdEnv = Platform.environment['MAGE_WEBSOCKET_AUTH_FILE_DESCRIPTOR'];
  if (fdEnv == null) {
    // No FD env var — try the well-known file.
    final path =
        Platform.environment['MAGE_SESSION_INGRESS_TOKEN_FILE'] ??
        _ccrSessionIngressTokenPath;
    _cachedSessionIngressToken = _readTokenFromWellKnownFile(path);
    _sessionIngressTokenChecked = true;
    return _cachedSessionIngressToken;
  }

  final fd = int.tryParse(fdEnv);
  if (fd == null) {
    _cachedSessionIngressToken = null;
    _sessionIngressTokenChecked = true;
    return null;
  }

  try {
    final fdPath = Platform.isMacOS ? '/dev/fd/$fd' : '/proc/self/fd/$fd';
    final token = File(fdPath).readAsStringSync().trim();
    if (token.isEmpty) {
      _cachedSessionIngressToken = null;
      _sessionIngressTokenChecked = true;
      return null;
    }
    _cachedSessionIngressToken = token;
    _sessionIngressTokenChecked = true;
    return token;
  } catch (_) {
    // FD read failed — try the well-known file.
    final path =
        Platform.environment['MAGE_SESSION_INGRESS_TOKEN_FILE'] ??
        _ccrSessionIngressTokenPath;
    _cachedSessionIngressToken = _readTokenFromWellKnownFile(path);
    _sessionIngressTokenChecked = true;
    return _cachedSessionIngressToken;
  }
}

/// Get session ingress authentication token.
/// Priority: env var > file descriptor > well-known file.
String? getSessionIngressAuthToken() {
  // 1. Check environment variable.
  final envToken = Platform.environment['MAGE_SESSION_ACCESS_TOKEN'];
  if (envToken != null && envToken.isNotEmpty) return envToken;

  // 2. Check file descriptor (legacy path), with file fallback.
  return _getTokenFromFileDescriptor();
}

/// Build auth headers for the current session token.
Map<String, String> getSessionIngressAuthHeaders() {
  final token = getSessionIngressAuthToken();
  if (token == null) return {};
  if (token.startsWith('sk-ant-sid')) {
    final headers = <String, String>{'Cookie': 'sessionKey=$token'};
    final orgUuid = Platform.environment['MAGE_ORGANIZATION_UUID'];
    if (orgUuid != null) {
      headers['X-Organization-Uuid'] = orgUuid;
    }
    return headers;
  }
  return {'Authorization': 'Bearer $token'};
}

/// Update the session ingress auth token in-process.
void updateSessionIngressAuthToken(String token) {
  // In Dart, we can't directly set env vars, so we use the cache.
  _cachedSessionIngressToken = token;
  _sessionIngressTokenChecked = true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Private helpers
// ═══════════════════════════════════════════════════════════════════════════

bool _isEnvTruthy(String? value) {
  if (value == null) return false;
  final v = value.toLowerCase().trim();
  return v == '1' || v == 'true' || v == 'yes';
}

String _getNeomageConfigHomeDir() {
  return Platform.environment['MAGE_CONFIG_HOME'] ??
      p.join(Platform.environment['HOME'] ?? '.', '.neomage');
}
