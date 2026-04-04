// Hook type definitions — port of neom_claw/src/hooks/types.ts.
// Defines all hook types, contexts, results, and registration structures
// used throughout the hook system.

import 'dart:async';

// ---------------------------------------------------------------------------
// Hook Type Enum
// ---------------------------------------------------------------------------

/// All hook points in the application lifecycle.
///
/// Hooks fire at well-defined points, allowing plugins and internal systems
/// to observe and modify behavior without direct coupling.
enum HookType {
  /// Fires before a tool is executed. Can modify input or block execution.
  preToolExecution,

  /// Fires after a tool completes. Can modify output or trigger follow-up.
  postToolExecution,

  /// Fires before a user or assistant message is processed.
  preMessage,

  /// Fires after a message has been processed and response generated.
  postMessage,

  /// Fires before an API call is made to the model provider.
  preApiCall,

  /// Fires after an API call completes (success or failure).
  postApiCall,

  /// Fires when an error occurs anywhere in the system.
  onError,

  /// Fires when a permission check is requested.
  onPermissionRequest,

  /// Fires after a permission decision has been made.
  onPermissionResult,

  /// Fires when a new session is started.
  onSessionStart,

  /// Fires when a session ends (graceful shutdown or timeout).
  onSessionEnd,

  /// Fires when a new conversation begins within a session.
  onConversationStart,

  /// Fires when a conversation ends.
  onConversationEnd,

  /// Fires when context compaction is performed.
  onCompaction,

  /// Fires when the conversation is forked into a sub-agent.
  onFork,

  /// Fires when a new tool is registered with the tool registry.
  onToolRegistration,

  /// Fires when a slash command is executed.
  onCommandExecution,

  /// Fires when a file is read, written, or deleted.
  onFileChange,

  /// Fires when a git operation is performed.
  onGitOperation,

  /// Fires when an MCP server connection is established.
  onMcpConnect,

  /// Fires when an MCP server connection is closed.
  onMcpDisconnect,

  /// Fires when a sub-agent is spawned.
  onAgentSpawn,

  /// Fires when a sub-agent completes its task.
  onAgentComplete,

  /// Fires when the UI theme changes.
  onThemeChange,

  /// Fires when configuration values change.
  onConfigChange,
}

// ---------------------------------------------------------------------------
// Hook Priority
// ---------------------------------------------------------------------------

/// Priority levels for hook execution ordering.
///
/// Hooks with lower numeric values run first. Use [critical] for security
/// hooks that must run before anything else, and [monitor] for passive
/// observation hooks that should not affect control flow.
enum HookPriority {
  /// Security and permission hooks that must run first (value: 0).
  critical(0),

  /// Important hooks that should run early (value: 25).
  high(25),

  /// Default priority for most hooks (value: 50).
  normal(50),

  /// Lower-priority hooks that run after normal processing (value: 75).
  low(75),

  /// Observation-only hooks that run last (value: 100).
  monitor(100);

  /// Numeric priority value. Lower values execute first.
  final int value;

  const HookPriority(this.value);

  /// Compare two priorities. Returns true if this runs before [other].
  bool runsBefore(HookPriority other) => value < other.value;
}

// ---------------------------------------------------------------------------
// Hook Context
// ---------------------------------------------------------------------------

/// Base context passed to every hook invocation.
///
/// Contains common metadata about the hook execution environment.
/// Specialized subclasses provide additional context for specific hook types.
class HookContext {
  /// The type of hook being executed.
  final HookType hookType;

  /// When this hook execution was initiated.
  final DateTime timestamp;

  /// The active session ID, if any.
  final String? sessionId;

  /// Arbitrary metadata that hooks can read and contribute to.
  final Map<String, dynamic> metadata;

  /// Results from previously executed hooks in the same chain.
  final List<HookResult> previousResults;

  /// The current conversation turn index, if applicable.
  final int? turnIndex;

  const HookContext({
    required this.hookType,
    required this.timestamp,
    this.sessionId,
    this.metadata = const {},
    this.previousResults = const [],
    this.turnIndex,
  });

  /// Create a copy with updated fields.
  HookContext copyWith({
    HookType? hookType,
    DateTime? timestamp,
    String? sessionId,
    Map<String, dynamic>? metadata,
    List<HookResult>? previousResults,
    int? turnIndex,
  }) {
    return HookContext(
      hookType: hookType ?? this.hookType,
      timestamp: timestamp ?? this.timestamp,
      sessionId: sessionId ?? this.sessionId,
      metadata: metadata ?? this.metadata,
      previousResults: previousResults ?? this.previousResults,
      turnIndex: turnIndex ?? this.turnIndex,
    );
  }

  /// Convenience constructor for the current time.
  factory HookContext.now({
    required HookType hookType,
    String? sessionId,
    Map<String, dynamic> metadata = const {},
    List<HookResult> previousResults = const [],
    int? turnIndex,
  }) {
    return HookContext(
      hookType: hookType,
      timestamp: DateTime.now(),
      sessionId: sessionId,
      metadata: metadata,
      previousResults: previousResults,
      turnIndex: turnIndex,
    );
  }
}

// ---------------------------------------------------------------------------
// Hook Result (Sealed)
// ---------------------------------------------------------------------------

/// Result returned by a hook handler, controlling chain behavior.
///
/// The hook executor interprets each variant to decide whether to continue,
/// skip, abort, retry, or transform data before passing to the next hook.
sealed class HookResult {
  const HookResult();
}

/// Continue execution with optionally modified data.
///
/// If [modifiedData] is non-null, subsequent hooks and the main execution
/// path will see the modified version.
class HookContinue extends HookResult {
  /// Optional modified data to pass forward. Null means no modification.
  final Map<String, dynamic>? modifiedData;

  const HookContinue({this.modifiedData});
}

/// Skip the current operation without error.
///
/// The hook chain continues, but the hooked operation itself may be skipped
/// depending on the hook type.
class HookSkip extends HookResult {
  /// Human-readable reason for skipping.
  final String reason;

  const HookSkip(this.reason);
}

/// Abort the entire hook chain and the hooked operation.
///
/// No further hooks in the chain will execute.
class HookAbort extends HookResult {
  /// Human-readable reason for aborting.
  final String reason;

  /// Optional underlying error that caused the abort.
  final Object? error;

  const HookAbort(this.reason, {this.error});
}

/// Request that the hooked operation be retried after a delay.
class HookRetry extends HookResult {
  /// How long to wait before retrying.
  final Duration delay;

  /// Maximum number of retry attempts (default: 1).
  final int maxAttempts;

  const HookRetry(this.delay, {this.maxAttempts = 1});
}

/// Transform the data flowing through the hook chain.
///
/// Unlike [HookContinue.modifiedData], this explicitly signals a
/// transformation and always replaces the current data.
class HookTransform extends HookResult {
  /// The transformed data.
  final Map<String, dynamic> data;

  const HookTransform(this.data);
}

// ---------------------------------------------------------------------------
// Specialized Hook Contexts
// ---------------------------------------------------------------------------

/// Context for tool-related hooks ([HookType.preToolExecution],
/// [HookType.postToolExecution]).
class ToolHookContext extends HookContext {
  /// Name of the tool being executed.
  final String toolName;

  /// Input arguments passed to the tool.
  final Map<String, dynamic> toolInput;

  /// Output from the tool (only set in post-execution hooks).
  final String? toolOutput;

  /// Whether the tool output is an error.
  final bool? toolIsError;

  /// Permission decision for this tool execution, if any.
  final String? permission;

  /// Duration of tool execution (only set in post-execution hooks).
  final Duration? executionDuration;

  const ToolHookContext({
    required super.hookType,
    required super.timestamp,
    super.sessionId,
    super.metadata,
    super.previousResults,
    super.turnIndex,
    required this.toolName,
    required this.toolInput,
    this.toolOutput,
    this.toolIsError,
    this.permission,
    this.executionDuration,
  });

  /// Create a post-execution context from a pre-execution context.
  ToolHookContext withOutput({
    required String output,
    bool isError = false,
    Duration? duration,
  }) {
    return ToolHookContext(
      hookType: HookType.postToolExecution,
      timestamp: DateTime.now(),
      sessionId: sessionId,
      metadata: metadata,
      previousResults: previousResults,
      turnIndex: turnIndex,
      toolName: toolName,
      toolInput: toolInput,
      toolOutput: output,
      toolIsError: isError,
      permission: permission,
      executionDuration: duration,
    );
  }
}

/// Context for message-related hooks ([HookType.preMessage],
/// [HookType.postMessage]).
class MessageHookContext extends HookContext {
  /// Role of the message sender (user, assistant, system).
  final String role;

  /// Text content of the message.
  final String content;

  /// Position of this message in the conversation turn sequence.
  final int messageTurnIndex;

  /// Optional list of tool use blocks in the message.
  final List<Map<String, dynamic>>? toolUseBlocks;

  /// Whether this message contains a stop sequence.
  final bool? hasStopSequence;

  const MessageHookContext({
    required super.hookType,
    required super.timestamp,
    super.sessionId,
    super.metadata,
    super.previousResults,
    super.turnIndex,
    required this.role,
    required this.content,
    required this.messageTurnIndex,
    this.toolUseBlocks,
    this.hasStopSequence,
  });
}

/// Context for API call hooks ([HookType.preApiCall], [HookType.postApiCall]).
class ApiHookContext extends HookContext {
  /// Model identifier (e.g., "claude-sonnet-4-20250514").
  final String model;

  /// Messages being sent to the API.
  final List<Map<String, dynamic>> messages;

  /// System prompt, if any.
  final String? systemPrompt;

  /// Sampling temperature.
  final double? temperature;

  /// Maximum tokens to generate.
  final int? maxTokens;

  /// Stop sequences, if any.
  final List<String>? stopSequences;

  /// Token usage from the response (only set in post-API hooks).
  final ApiTokenUsage? tokenUsage;

  /// Response latency (only set in post-API hooks).
  final Duration? latency;

  /// HTTP status code (only set in post-API hooks).
  final int? statusCode;

  const ApiHookContext({
    required super.hookType,
    required super.timestamp,
    super.sessionId,
    super.metadata,
    super.previousResults,
    super.turnIndex,
    required this.model,
    required this.messages,
    this.systemPrompt,
    this.temperature,
    this.maxTokens,
    this.stopSequences,
    this.tokenUsage,
    this.latency,
    this.statusCode,
  });

  /// Create a post-API context with response information.
  ApiHookContext withResponse({
    ApiTokenUsage? tokenUsage,
    Duration? latency,
    int? statusCode,
  }) {
    return ApiHookContext(
      hookType: HookType.postApiCall,
      timestamp: DateTime.now(),
      sessionId: sessionId,
      metadata: metadata,
      previousResults: previousResults,
      turnIndex: turnIndex,
      model: model,
      messages: messages,
      systemPrompt: systemPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
      stopSequences: stopSequences,
      tokenUsage: tokenUsage,
      latency: latency,
      statusCode: statusCode,
    );
  }
}

/// Token usage reported by the API.
class ApiTokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;

  const ApiTokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });

  int get totalTokens => inputTokens + outputTokens;
}

/// Context for file-related hooks ([HookType.onFileChange]).
class FileHookContext extends HookContext {
  /// Absolute path of the file.
  final String path;

  /// Operation being performed.
  final FileOperation operation;

  /// File content (for write operations, the new content; for read, the
  /// content that was read).
  final String? content;

  /// Previous content before modification (for write/delete).
  final String? previousContent;

  /// Size of the file in bytes.
  final int? fileSize;

  const FileHookContext({
    required super.hookType,
    required super.timestamp,
    super.sessionId,
    super.metadata,
    super.previousResults,
    super.turnIndex,
    required this.path,
    required this.operation,
    this.content,
    this.previousContent,
    this.fileSize,
  });
}

/// File operations tracked by [FileHookContext].
enum FileOperation { read, write, delete, create, rename, chmod }

/// Context for git-related hooks ([HookType.onGitOperation]).
class GitHookContext extends HookContext {
  /// Git operation being performed.
  final GitOperation operation;

  /// Current branch name.
  final String? branch;

  /// Target branch (for merge, rebase, checkout).
  final String? targetBranch;

  /// Files involved in the operation.
  final List<String> files;

  /// Remote name (for push, pull, fetch).
  final String? remote;

  /// Commit message (for commit operations).
  final String? commitMessage;

  /// Whether the operation is forced (e.g., force push).
  final bool force;

  const GitHookContext({
    required super.hookType,
    required super.timestamp,
    super.sessionId,
    super.metadata,
    super.previousResults,
    super.turnIndex,
    required this.operation,
    this.branch,
    this.targetBranch,
    this.files = const [],
    this.remote,
    this.commitMessage,
    this.force = false,
  });
}

/// Git operations tracked by [GitHookContext].
enum GitOperation {
  commit,
  push,
  pull,
  fetch,
  merge,
  rebase,
  checkout,
  branch,
  tag,
  stash,
  reset,
  revert,
  cherryPick,
  clone,
  init,
}

/// Context for error hooks ([HookType.onError]).
class ErrorHookContext extends HookContext {
  /// The error that occurred.
  final Object error;

  /// Stack trace at the point of the error.
  final StackTrace? stackTrace;

  /// Whether the error is potentially recoverable.
  final bool recoverable;

  /// Error category for grouping and filtering.
  final String? errorCategory;

  /// The component or subsystem where the error originated.
  final String? source;

  /// Number of times this error has been retried.
  final int retryCount;

  const ErrorHookContext({
    required super.hookType,
    required super.timestamp,
    super.sessionId,
    super.metadata,
    super.previousResults,
    super.turnIndex,
    required this.error,
    this.stackTrace,
    required this.recoverable,
    this.errorCategory,
    this.source,
    this.retryCount = 0,
  });
}

// ---------------------------------------------------------------------------
// Hook Registration
// ---------------------------------------------------------------------------

/// Signature for synchronous hook handlers.
typedef HookHandler = HookResult Function(HookContext context);

/// Signature for asynchronous hook handlers.
typedef AsyncHookHandler = Future<HookResult> Function(HookContext context);

/// Signature for hook matchers that determine whether a hook should fire.
typedef HookMatcher = bool Function(HookContext context);

/// Registration record for a single hook handler.
///
/// Created when a hook is registered with [HookExecutor.register] and used
/// to manage the hook's lifecycle (enable/disable/unregister).
class HookRegistration {
  /// Unique identifier for this registration.
  final String id;

  /// Which hook type this registration listens to.
  final HookType type;

  /// Execution priority. Lower [HookPriority.value] runs first.
  final HookPriority priority;

  /// Human-readable name for debugging and logging.
  final String name;

  /// Optional description of what this hook does.
  final String? description;

  /// Whether this hook is currently active.
  bool enabled;

  /// Optional matcher that filters which contexts trigger this hook.
  /// If null, the hook fires for all contexts of the matching [type].
  final HookMatcher? matcher;

  /// The synchronous handler function. Exactly one of [handler] or
  /// [asyncHandler] must be non-null.
  final HookHandler? handler;

  /// The asynchronous handler function. Exactly one of [handler] or
  /// [asyncHandler] must be non-null.
  final AsyncHookHandler? asyncHandler;

  /// Source identifier (e.g., plugin name, "builtin", "user").
  final String? source;

  /// Tags for categorization and filtering.
  final Set<String> tags;

  /// When this hook was registered.
  final DateTime registeredAt;

  HookRegistration({
    required this.id,
    required this.type,
    this.priority = HookPriority.normal,
    required this.name,
    this.description,
    this.enabled = true,
    this.matcher,
    this.handler,
    this.asyncHandler,
    this.source,
    this.tags = const {},
    DateTime? registeredAt,
  }) : registeredAt = registeredAt ?? DateTime.now(),
       assert(
         handler != null || asyncHandler != null,
         'Either handler or asyncHandler must be provided',
       );

  /// Whether this hook uses an async handler.
  bool get isAsync => asyncHandler != null;

  /// Execute this hook's handler (sync or async) and return the result.
  Future<HookResult> execute(HookContext context) async {
    if (asyncHandler != null) {
      return asyncHandler!(context);
    }
    return handler!(context);
  }
}

// ---------------------------------------------------------------------------
// Hook Chain
// ---------------------------------------------------------------------------

/// An ordered list of [HookRegistration]s for a single [HookType],
/// sorted by priority (lower values first).
class HookChain {
  final HookType type;
  final List<HookRegistration> _registrations;

  HookChain({required this.type}) : _registrations = [];

  /// All registrations, sorted by priority.
  List<HookRegistration> get registrations => List.unmodifiable(_registrations);

  /// Only enabled registrations, sorted by priority.
  List<HookRegistration> get activeRegistrations =>
      _registrations.where((r) => r.enabled).toList();

  /// Number of registered hooks.
  int get length => _registrations.length;

  /// Number of enabled hooks.
  int get activeLength => _registrations.where((r) => r.enabled).length;

  /// Whether the chain has no hooks.
  bool get isEmpty => _registrations.isEmpty;

  /// Add a registration, maintaining priority sort order.
  void add(HookRegistration registration) {
    assert(
      registration.type == type,
      'Registration type ${registration.type} does not match chain type $type',
    );
    _registrations.add(registration);
    _registrations.sort((a, b) => a.priority.value.compareTo(b.priority.value));
  }

  /// Remove a registration by ID. Returns true if found and removed.
  bool remove(String id) {
    final index = _registrations.indexWhere((r) => r.id == id);
    if (index == -1) return false;
    _registrations.removeAt(index);
    return true;
  }

  /// Find a registration by ID.
  HookRegistration? find(String id) {
    for (final reg in _registrations) {
      if (reg.id == id) return reg;
    }
    return null;
  }

  /// Remove all registrations from a given source.
  int removeBySource(String source) {
    final before = _registrations.length;
    _registrations.removeWhere((r) => r.source == source);
    return before - _registrations.length;
  }

  /// Remove all registrations.
  void clear() => _registrations.clear();
}
