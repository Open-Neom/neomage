// Lifecycle hooks — port of neom_claw/src/hooks/lifecycle.ts.
// Defines lifecycle callbacks for sessions, conversations, tools, and agents,
// along with a sealed event hierarchy and a manager that wires everything
// into the HookExecutor.

import 'dart:async';

import 'hook_types.dart';
import 'hook_executor.dart';

// ---------------------------------------------------------------------------
// Session Lifecycle
// ---------------------------------------------------------------------------

/// Callbacks for session-level lifecycle events.
///
/// A session spans from the moment the CLI starts to when it exits.
/// Implementations can track cost, enforce timeouts, or persist state.
class SessionLifecycle {
  /// Fired when a new session begins.
  final Future<void> Function(SessionStartedEvent event)? onSessionStart;

  /// Fired when the session ends (graceful shutdown or timeout).
  final Future<void> Function(SessionEndedEvent event)? onSessionEnd;

  /// Fired when the session is paused (e.g., backgrounded).
  final Future<void> Function(SessionPausedEvent event)? onSessionPause;

  /// Fired when the session resumes from a paused state.
  final Future<void> Function(SessionResumedEvent event)? onSessionResume;

  const SessionLifecycle({
    this.onSessionStart,
    this.onSessionEnd,
    this.onSessionPause,
    this.onSessionResume,
  });
}

// ---------------------------------------------------------------------------
// Conversation Lifecycle
// ---------------------------------------------------------------------------

/// Callbacks for conversation-level lifecycle events.
///
/// A conversation is a sequence of turns within a session. Multiple
/// conversations can occur per session (e.g., when using /clear).
class ConversationLifecycle {
  /// Fired when a new conversation begins.
  final Future<void> Function(ConversationStartedEvent event)?
  onConversationStart;

  /// Fired at the beginning of each user turn.
  final Future<void> Function(TurnStartedEvent event)? onTurnStart;

  /// Fired after each turn completes (response sent to user).
  final Future<void> Function(TurnEndedEvent event)? onTurnEnd;

  /// Fired when the conversation ends.
  final Future<void> Function(ConversationEndedEvent event)? onConversationEnd;

  /// Fired when context compaction occurs (message history trimming).
  final Future<void> Function(CompactionEvent event)? onCompaction;

  const ConversationLifecycle({
    this.onConversationStart,
    this.onTurnStart,
    this.onTurnEnd,
    this.onConversationEnd,
    this.onCompaction,
  });
}

// ---------------------------------------------------------------------------
// Tool Lifecycle
// ---------------------------------------------------------------------------

/// Callbacks for tool-level lifecycle events.
///
/// Allows observation and modification of tool execution at each stage.
class ToolLifecycle {
  /// Fired when a new tool is registered with the tool registry.
  final Future<void> Function(ToolRegisteredEvent event)? onToolRegistered;

  /// Fired before a tool executes. Can return modified input.
  ///
  /// If the returned map is non-null, it replaces the original tool input.
  final Future<Map<String, dynamic>?> Function(ToolBeforeExecutionEvent event)?
  onToolBeforeExecution;

  /// Fired after a tool executes successfully. Can return modified output.
  ///
  /// If the returned string is non-null, it replaces the original output.
  final Future<String?> Function(ToolAfterExecutionEvent event)?
  onToolAfterExecution;

  /// Fired when a tool encounters an error. Can return a recovery action.
  ///
  /// The returned [ToolRecoveryAction] tells the system how to proceed.
  final Future<ToolRecoveryAction> Function(ToolErrorEvent event)? onToolError;

  /// Fired when a tool execution times out.
  final Future<void> Function(ToolTimeoutEvent event)? onToolTimeout;

  const ToolLifecycle({
    this.onToolRegistered,
    this.onToolBeforeExecution,
    this.onToolAfterExecution,
    this.onToolError,
    this.onToolTimeout,
  });
}

/// Actions available when recovering from a tool error.
enum ToolRecoveryAction {
  /// Let the error propagate normally.
  propagate,

  /// Retry the tool execution with the same input.
  retry,

  /// Retry the tool execution with modified input.
  retryWithModifiedInput,

  /// Suppress the error and return a default/empty result.
  suppress,

  /// Abort the current turn entirely.
  abortTurn,
}

// ---------------------------------------------------------------------------
// Agent Lifecycle
// ---------------------------------------------------------------------------

/// Callbacks for sub-agent lifecycle events.
///
/// Sub-agents are forked conversations that run in parallel.
class AgentLifecycle {
  /// Fired when a sub-agent is spawned.
  final Future<void> Function(AgentSpawnedEvent event)? onAgentSpawned;

  /// Fired when a sub-agent sends a message or update.
  final Future<void> Function(AgentMessageEvent event)? onAgentMessage;

  /// Fired when a sub-agent completes its task.
  final Future<void> Function(AgentCompletedEvent event)? onAgentCompleted;

  /// Fired when a sub-agent encounters an error.
  final Future<void> Function(AgentErrorEvent event)? onAgentError;

  /// Fired when a sub-agent times out.
  final Future<void> Function(AgentTimeoutEvent event)? onAgentTimeout;

  const AgentLifecycle({
    this.onAgentSpawned,
    this.onAgentMessage,
    this.onAgentCompleted,
    this.onAgentError,
    this.onAgentTimeout,
  });
}

// ---------------------------------------------------------------------------
// Lifecycle Event (Sealed Hierarchy)
// ---------------------------------------------------------------------------

/// Base class for all lifecycle events.
///
/// Uses Dart's sealed class feature to provide exhaustive pattern matching
/// across all event types.
sealed class LifecycleEvent {
  /// When this event occurred.
  final DateTime timestamp;

  /// The session ID this event belongs to.
  final String? sessionId;

  /// Arbitrary metadata attached to the event.
  final Map<String, dynamic> metadata;

  const LifecycleEvent({
    required this.timestamp,
    this.sessionId,
    this.metadata = const {},
  });

  /// Human-readable event type name.
  String get eventType;
}

// -- Session Events --

class SessionStartedEvent extends LifecycleEvent {
  /// Working directory for this session.
  final String? workingDirectory;

  /// Configuration profile name.
  final String? profile;

  /// Whether this is a resumed session.
  final bool isResume;

  const SessionStartedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    this.workingDirectory,
    this.profile,
    this.isResume = false,
  });

  @override
  String get eventType => 'SessionStarted';
}

class SessionEndedEvent extends LifecycleEvent {
  /// Reason the session ended.
  final String reason;

  /// Total duration of the session.
  final Duration duration;

  /// Total tokens used during the session.
  final int totalTokens;

  /// Estimated cost for the session.
  final double estimatedCost;

  const SessionEndedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.reason,
    required this.duration,
    this.totalTokens = 0,
    this.estimatedCost = 0.0,
  });

  @override
  String get eventType => 'SessionEnded';
}

class SessionPausedEvent extends LifecycleEvent {
  /// Reason for the pause.
  final String? reason;

  const SessionPausedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    this.reason,
  });

  @override
  String get eventType => 'SessionPaused';
}

class SessionResumedEvent extends LifecycleEvent {
  /// How long the session was paused.
  final Duration pauseDuration;

  const SessionResumedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.pauseDuration,
  });

  @override
  String get eventType => 'SessionResumed';
}

// -- Conversation Events --

class ConversationStartedEvent extends LifecycleEvent {
  /// Unique conversation ID.
  final String conversationId;

  /// Whether this conversation continues from a previous one.
  final bool isContinuation;

  const ConversationStartedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.conversationId,
    this.isContinuation = false,
  });

  @override
  String get eventType => 'ConversationStarted';
}

class ConversationEndedEvent extends LifecycleEvent {
  /// Unique conversation ID.
  final String conversationId;

  /// Number of turns in the conversation.
  final int turnCount;

  /// Total tokens used in the conversation.
  final int totalTokens;

  const ConversationEndedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.conversationId,
    this.turnCount = 0,
    this.totalTokens = 0,
  });

  @override
  String get eventType => 'ConversationEnded';
}

class TurnStartedEvent extends LifecycleEvent {
  /// The turn number (0-indexed).
  final int turnIndex;

  /// The user's input message for this turn.
  final String userMessage;

  const TurnStartedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.turnIndex,
    required this.userMessage,
  });

  @override
  String get eventType => 'TurnStarted';
}

class TurnEndedEvent extends LifecycleEvent {
  /// The turn number (0-indexed).
  final int turnIndex;

  /// Tokens used during this turn.
  final int tokensUsed;

  /// Number of tool invocations during this turn.
  final int toolInvocations;

  /// Duration of the turn.
  final Duration duration;

  const TurnEndedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.turnIndex,
    this.tokensUsed = 0,
    this.toolInvocations = 0,
    required this.duration,
  });

  @override
  String get eventType => 'TurnEnded';
}

class CompactionEvent extends LifecycleEvent {
  /// Number of messages before compaction.
  final int messagesBefore;

  /// Number of messages after compaction.
  final int messagesAfter;

  /// Token count before compaction.
  final int tokensBefore;

  /// Token count after compaction.
  final int tokensAfter;

  const CompactionEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.messagesBefore,
    required this.messagesAfter,
    required this.tokensBefore,
    required this.tokensAfter,
  });

  @override
  String get eventType => 'Compaction';

  /// Number of messages removed.
  int get messagesRemoved => messagesBefore - messagesAfter;

  /// Number of tokens saved.
  int get tokensSaved => tokensBefore - tokensAfter;
}

// -- Tool Events --

class ToolRegisteredEvent extends LifecycleEvent {
  /// Name of the registered tool.
  final String toolName;

  /// Source of the tool (e.g., "builtin", "mcp:server-name").
  final String source;

  const ToolRegisteredEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.toolName,
    required this.source,
  });

  @override
  String get eventType => 'ToolRegistered';
}

class ToolBeforeExecutionEvent extends LifecycleEvent {
  /// Name of the tool about to execute.
  final String toolName;

  /// Input arguments.
  final Map<String, dynamic> input;

  const ToolBeforeExecutionEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.toolName,
    required this.input,
  });

  @override
  String get eventType => 'ToolBeforeExecution';
}

class ToolAfterExecutionEvent extends LifecycleEvent {
  /// Name of the tool that executed.
  final String toolName;

  /// Input arguments that were provided.
  final Map<String, dynamic> input;

  /// Output from the tool.
  final String output;

  /// Whether the output is an error.
  final bool isError;

  /// How long the tool took to execute.
  final Duration executionDuration;

  const ToolAfterExecutionEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.toolName,
    required this.input,
    required this.output,
    this.isError = false,
    required this.executionDuration,
  });

  @override
  String get eventType => 'ToolAfterExecution';
}

class ToolErrorEvent extends LifecycleEvent {
  /// Name of the tool that failed.
  final String toolName;

  /// Input arguments that were provided.
  final Map<String, dynamic> input;

  /// The error that occurred.
  final Object error;

  /// Stack trace for the error.
  final StackTrace? stackTrace;

  const ToolErrorEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.toolName,
    required this.input,
    required this.error,
    this.stackTrace,
  });

  @override
  String get eventType => 'ToolError';
}

class ToolTimeoutEvent extends LifecycleEvent {
  /// Name of the tool that timed out.
  final String toolName;

  /// Input arguments that were provided.
  final Map<String, dynamic> input;

  /// The timeout duration that was exceeded.
  final Duration timeoutDuration;

  const ToolTimeoutEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.toolName,
    required this.input,
    required this.timeoutDuration,
  });

  @override
  String get eventType => 'ToolTimeout';
}

// -- Agent Events --

class AgentSpawnedEvent extends LifecycleEvent {
  /// Unique ID for the spawned agent.
  final String agentId;

  /// The task/prompt given to the agent.
  final String task;

  /// Parent session or agent ID.
  final String? parentId;

  const AgentSpawnedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.agentId,
    required this.task,
    this.parentId,
  });

  @override
  String get eventType => 'AgentSpawned';
}

class AgentMessageEvent extends LifecycleEvent {
  /// ID of the agent that sent the message.
  final String agentId;

  /// The message content.
  final String message;

  /// Message type (progress, result, error).
  final String messageType;

  const AgentMessageEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.agentId,
    required this.message,
    this.messageType = 'progress',
  });

  @override
  String get eventType => 'AgentMessage';
}

class AgentCompletedEvent extends LifecycleEvent {
  /// ID of the agent that completed.
  final String agentId;

  /// The agent's result/output.
  final String result;

  /// Total duration of the agent's execution.
  final Duration duration;

  /// Total tokens used by the agent.
  final int tokensUsed;

  const AgentCompletedEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.agentId,
    required this.result,
    required this.duration,
    this.tokensUsed = 0,
  });

  @override
  String get eventType => 'AgentCompleted';
}

class AgentErrorEvent extends LifecycleEvent {
  /// ID of the agent that errored.
  final String agentId;

  /// The error that occurred.
  final Object error;

  /// Stack trace for the error.
  final StackTrace? stackTrace;

  /// Whether the error is recoverable.
  final bool recoverable;

  const AgentErrorEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.agentId,
    required this.error,
    this.stackTrace,
    this.recoverable = false,
  });

  @override
  String get eventType => 'AgentError';
}

class AgentTimeoutEvent extends LifecycleEvent {
  /// ID of the agent that timed out.
  final String agentId;

  /// The timeout duration that was exceeded.
  final Duration timeoutDuration;

  const AgentTimeoutEvent({
    required super.timestamp,
    super.sessionId,
    super.metadata,
    required this.agentId,
    required this.timeoutDuration,
  });

  @override
  String get eventType => 'AgentTimeout';
}

// ---------------------------------------------------------------------------
// Lifecycle Manager
// ---------------------------------------------------------------------------

/// Registers lifecycle callbacks as hooks with a [HookExecutor].
///
/// Translates the typed lifecycle callback interfaces into generic
/// [HookRegistration]s so that all lifecycle events flow through the
/// unified hook system.
class LifecycleManager {
  final HookExecutor _executor;
  final List<String> _registeredIds = [];

  /// Stream controller for lifecycle events (separate from hook events).
  final StreamController<LifecycleEvent> _eventController =
      StreamController<LifecycleEvent>.broadcast();

  LifecycleManager({required HookExecutor executor}) : _executor = executor;

  /// Stream of lifecycle events for observation.
  Stream<LifecycleEvent> get events => _eventController.stream;

  /// Register session lifecycle callbacks.
  void registerSession(SessionLifecycle lifecycle) {
    if (lifecycle.onSessionStart != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:session:start',
          type: HookType.onSessionStart,
          priority: HookPriority.normal,
          name: 'Session Start Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = SessionStartedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              workingDirectory: context.metadata['workingDirectory'] as String?,
              profile: context.metadata['profile'] as String?,
              isResume: context.metadata['isResume'] as bool? ?? false,
            );
            await lifecycle.onSessionStart!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onSessionEnd != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:session:end',
          type: HookType.onSessionEnd,
          priority: HookPriority.normal,
          name: 'Session End Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = SessionEndedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              reason: context.metadata['reason'] as String? ?? 'unknown',
              duration:
                  context.metadata['duration'] as Duration? ?? Duration.zero,
              totalTokens: context.metadata['totalTokens'] as int? ?? 0,
              estimatedCost:
                  context.metadata['estimatedCost'] as double? ?? 0.0,
            );
            await lifecycle.onSessionEnd!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onSessionPause != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:session:pause',
          type: HookType.onSessionEnd, // Reuse session-end with metadata flag
          priority: HookPriority.normal,
          name: 'Session Pause Lifecycle',
          source: 'lifecycle',
          matcher: (context) => context.metadata['isPause'] == true,
          asyncHandler: (context) async {
            final event = SessionPausedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              reason: context.metadata['reason'] as String?,
            );
            await lifecycle.onSessionPause!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onSessionResume != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:session:resume',
          type: HookType.onSessionStart, // Reuse with metadata flag
          priority: HookPriority.normal,
          name: 'Session Resume Lifecycle',
          source: 'lifecycle',
          matcher: (context) => context.metadata['isResume'] == true,
          asyncHandler: (context) async {
            final event = SessionResumedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              pauseDuration:
                  context.metadata['pauseDuration'] as Duration? ??
                  Duration.zero,
            );
            await lifecycle.onSessionResume!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }
  }

  /// Register conversation lifecycle callbacks.
  void registerConversation(ConversationLifecycle lifecycle) {
    if (lifecycle.onConversationStart != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:conversation:start',
          type: HookType.onConversationStart,
          priority: HookPriority.normal,
          name: 'Conversation Start Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = ConversationStartedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              conversationId:
                  context.metadata['conversationId'] as String? ?? '',
              isContinuation:
                  context.metadata['isContinuation'] as bool? ?? false,
            );
            await lifecycle.onConversationStart!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onTurnStart != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:turn:start',
          type: HookType.preMessage,
          priority: HookPriority.normal,
          name: 'Turn Start Lifecycle',
          source: 'lifecycle',
          matcher: (context) =>
              context is MessageHookContext && context.role == 'user',
          asyncHandler: (context) async {
            final event = TurnStartedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              turnIndex: context.turnIndex ?? 0,
              userMessage: context is MessageHookContext ? context.content : '',
            );
            await lifecycle.onTurnStart!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onTurnEnd != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:turn:end',
          type: HookType.postMessage,
          priority: HookPriority.normal,
          name: 'Turn End Lifecycle',
          source: 'lifecycle',
          matcher: (context) =>
              context is MessageHookContext && context.role == 'assistant',
          asyncHandler: (context) async {
            final event = TurnEndedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              turnIndex: context.turnIndex ?? 0,
              tokensUsed: context.metadata['tokensUsed'] as int? ?? 0,
              toolInvocations: context.metadata['toolInvocations'] as int? ?? 0,
              duration:
                  context.metadata['turnDuration'] as Duration? ??
                  Duration.zero,
            );
            await lifecycle.onTurnEnd!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onConversationEnd != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:conversation:end',
          type: HookType.onConversationEnd,
          priority: HookPriority.normal,
          name: 'Conversation End Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = ConversationEndedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              conversationId:
                  context.metadata['conversationId'] as String? ?? '',
              turnCount: context.metadata['turnCount'] as int? ?? 0,
              totalTokens: context.metadata['totalTokens'] as int? ?? 0,
            );
            await lifecycle.onConversationEnd!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onCompaction != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:compaction',
          type: HookType.onCompaction,
          priority: HookPriority.normal,
          name: 'Compaction Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = CompactionEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              messagesBefore: context.metadata['messagesBefore'] as int? ?? 0,
              messagesAfter: context.metadata['messagesAfter'] as int? ?? 0,
              tokensBefore: context.metadata['tokensBefore'] as int? ?? 0,
              tokensAfter: context.metadata['tokensAfter'] as int? ?? 0,
            );
            await lifecycle.onCompaction!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }
  }

  /// Register tool lifecycle callbacks.
  void registerTool(ToolLifecycle lifecycle) {
    if (lifecycle.onToolRegistered != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:tool:registered',
          type: HookType.onToolRegistration,
          priority: HookPriority.normal,
          name: 'Tool Registered Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = ToolRegisteredEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              toolName: context.metadata['toolName'] as String? ?? '',
              source: context.metadata['source'] as String? ?? 'unknown',
            );
            await lifecycle.onToolRegistered!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onToolBeforeExecution != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:tool:before',
          type: HookType.preToolExecution,
          priority: HookPriority.normal,
          name: 'Tool Before Execution Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            if (context is! ToolHookContext) return const HookContinue();
            final event = ToolBeforeExecutionEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              toolName: context.toolName,
              input: context.toolInput,
            );
            final modifiedInput = await lifecycle.onToolBeforeExecution!(event);
            _emitEvent(event);
            if (modifiedInput != null) {
              return HookTransform(modifiedInput);
            }
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onToolAfterExecution != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:tool:after',
          type: HookType.postToolExecution,
          priority: HookPriority.normal,
          name: 'Tool After Execution Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            if (context is! ToolHookContext) return const HookContinue();
            final event = ToolAfterExecutionEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              toolName: context.toolName,
              input: context.toolInput,
              output: context.toolOutput ?? '',
              isError: context.toolIsError ?? false,
              executionDuration: context.executionDuration ?? Duration.zero,
            );
            final modifiedOutput = await lifecycle.onToolAfterExecution!(event);
            _emitEvent(event);
            if (modifiedOutput != null) {
              return HookTransform({'output': modifiedOutput});
            }
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onToolError != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:tool:error',
          type: HookType.onError,
          priority: HookPriority.normal,
          name: 'Tool Error Lifecycle',
          source: 'lifecycle',
          matcher: (context) =>
              context is ErrorHookContext && context.source == 'tool',
          asyncHandler: (context) async {
            if (context is! ErrorHookContext) return const HookContinue();
            final event = ToolErrorEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              toolName: context.metadata['toolName'] as String? ?? '',
              input:
                  context.metadata['toolInput'] as Map<String, dynamic>? ?? {},
              error: context.error,
              stackTrace: context.stackTrace,
            );
            final action = await lifecycle.onToolError!(event);
            _emitEvent(event);
            return switch (action) {
              ToolRecoveryAction.propagate => const HookContinue(),
              ToolRecoveryAction.retry => const HookRetry(Duration(seconds: 1)),
              ToolRecoveryAction.retryWithModifiedInput => const HookRetry(
                Duration(seconds: 1),
              ),
              ToolRecoveryAction.suppress => const HookSkip('Error suppressed'),
              ToolRecoveryAction.abortTurn => const HookAbort(
                'Turn aborted due to tool error',
              ),
            };
          },
        ),
      );
    }

    if (lifecycle.onToolTimeout != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:tool:timeout',
          type: HookType.onError,
          priority: HookPriority.normal,
          name: 'Tool Timeout Lifecycle',
          source: 'lifecycle',
          matcher: (context) =>
              context is ErrorHookContext &&
              context.errorCategory == 'timeout' &&
              context.source == 'tool',
          asyncHandler: (context) async {
            if (context is! ErrorHookContext) return const HookContinue();
            final event = ToolTimeoutEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              toolName: context.metadata['toolName'] as String? ?? '',
              input:
                  context.metadata['toolInput'] as Map<String, dynamic>? ?? {},
              timeoutDuration:
                  context.metadata['timeout'] as Duration? ??
                  const Duration(seconds: 30),
            );
            await lifecycle.onToolTimeout!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }
  }

  /// Register agent lifecycle callbacks.
  void registerAgent(AgentLifecycle lifecycle) {
    if (lifecycle.onAgentSpawned != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:agent:spawned',
          type: HookType.onAgentSpawn,
          priority: HookPriority.normal,
          name: 'Agent Spawned Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = AgentSpawnedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              agentId: context.metadata['agentId'] as String? ?? '',
              task: context.metadata['task'] as String? ?? '',
              parentId: context.metadata['parentId'] as String?,
            );
            await lifecycle.onAgentSpawned!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onAgentMessage != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:agent:message',
          type: HookType.onFork, // Reuse fork hook for agent messages
          priority: HookPriority.normal,
          name: 'Agent Message Lifecycle',
          source: 'lifecycle',
          matcher: (context) => context.metadata['eventType'] == 'agentMessage',
          asyncHandler: (context) async {
            final event = AgentMessageEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              agentId: context.metadata['agentId'] as String? ?? '',
              message: context.metadata['message'] as String? ?? '',
              messageType:
                  context.metadata['messageType'] as String? ?? 'progress',
            );
            await lifecycle.onAgentMessage!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onAgentCompleted != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:agent:completed',
          type: HookType.onAgentComplete,
          priority: HookPriority.normal,
          name: 'Agent Completed Lifecycle',
          source: 'lifecycle',
          asyncHandler: (context) async {
            final event = AgentCompletedEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              agentId: context.metadata['agentId'] as String? ?? '',
              result: context.metadata['result'] as String? ?? '',
              duration:
                  context.metadata['duration'] as Duration? ?? Duration.zero,
              tokensUsed: context.metadata['tokensUsed'] as int? ?? 0,
            );
            await lifecycle.onAgentCompleted!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onAgentError != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:agent:error',
          type: HookType.onError,
          priority: HookPriority.normal,
          name: 'Agent Error Lifecycle',
          source: 'lifecycle',
          matcher: (context) =>
              context is ErrorHookContext && context.source == 'agent',
          asyncHandler: (context) async {
            if (context is! ErrorHookContext) return const HookContinue();
            final event = AgentErrorEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              agentId: context.metadata['agentId'] as String? ?? '',
              error: context.error,
              stackTrace: context.stackTrace,
              recoverable: context.recoverable,
            );
            await lifecycle.onAgentError!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }

    if (lifecycle.onAgentTimeout != null) {
      _register(
        HookRegistration(
          id: 'lifecycle:agent:timeout',
          type: HookType.onError,
          priority: HookPriority.normal,
          name: 'Agent Timeout Lifecycle',
          source: 'lifecycle',
          matcher: (context) =>
              context is ErrorHookContext &&
              context.errorCategory == 'timeout' &&
              context.source == 'agent',
          asyncHandler: (context) async {
            if (context is! ErrorHookContext) return const HookContinue();
            final event = AgentTimeoutEvent(
              timestamp: context.timestamp,
              sessionId: context.sessionId,
              metadata: context.metadata,
              agentId: context.metadata['agentId'] as String? ?? '',
              timeoutDuration:
                  context.metadata['timeout'] as Duration? ??
                  const Duration(minutes: 5),
            );
            await lifecycle.onAgentTimeout!(event);
            _emitEvent(event);
            return const HookContinue();
          },
        ),
      );
    }
  }

  /// Register all lifecycle types at once.
  void registerAll({
    SessionLifecycle? session,
    ConversationLifecycle? conversation,
    ToolLifecycle? tool,
    AgentLifecycle? agent,
  }) {
    if (session != null) registerSession(session);
    if (conversation != null) registerConversation(conversation);
    if (tool != null) registerTool(tool);
    if (agent != null) registerAgent(agent);
  }

  /// Unregister all lifecycle hooks.
  void unregisterAll() {
    for (final id in _registeredIds) {
      _executor.unregister(id);
    }
    _registeredIds.clear();
  }

  /// Dispose the lifecycle manager and close the event stream.
  void dispose() {
    unregisterAll();
    _eventController.close();
  }

  // -- Private helpers --

  void _register(HookRegistration registration) {
    _executor.register(registration);
    _registeredIds.add(registration.id);
  }

  void _emitEvent(LifecycleEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}

// ---------------------------------------------------------------------------
// Built-In Lifecycle Hooks
// ---------------------------------------------------------------------------

/// Pre-configured lifecycle hooks that implement common operational concerns.
///
/// Each method returns a typed lifecycle callback set that can be registered
/// with a [LifecycleManager].
class BuiltInLifecycleHooks {
  BuiltInLifecycleHooks._();

  /// Cost tracking lifecycle hooks.
  ///
  /// Tracks cumulative token usage and estimated cost across the session,
  /// emitting summaries at turn end and session end.
  static SessionLifecycle costTracking({
    required void Function(
      int totalInputTokens,
      int totalOutputTokens,
      double estimatedCost,
    )
    onCostUpdate,
    double inputTokenCost = 0.000003,
    double outputTokenCost = 0.000015,
  }) {
    var totalInput = 0;
    var totalOutput = 0;
    var totalCost = 0.0;
    DateTime? sessionStart;

    return SessionLifecycle(
      onSessionStart: (event) async {
        sessionStart = event.timestamp;
        totalInput = 0;
        totalOutput = 0;
        totalCost = 0.0;
      },
      onSessionEnd: (event) async {
        onCostUpdate(totalInput, totalOutput, totalCost);
      },
    );
  }

  /// Audit log lifecycle hooks.
  ///
  /// Logs key lifecycle events (session start/end, tool executions) to
  /// a provided callback for persistence or monitoring.
  static ConversationLifecycle auditLog({
    required void Function(String entry) log,
  }) {
    return ConversationLifecycle(
      onConversationStart: (event) async {
        log(
          '[${event.timestamp.toIso8601String()}] '
          'Conversation started: ${event.conversationId}',
        );
      },
      onTurnStart: (event) async {
        log(
          '[${event.timestamp.toIso8601String()}] '
          'Turn ${event.turnIndex} started',
        );
      },
      onTurnEnd: (event) async {
        log(
          '[${event.timestamp.toIso8601String()}] '
          'Turn ${event.turnIndex} ended '
          '(tokens: ${event.tokensUsed}, '
          'tools: ${event.toolInvocations}, '
          'duration: ${event.duration.inMilliseconds}ms)',
        );
      },
      onConversationEnd: (event) async {
        log(
          '[${event.timestamp.toIso8601String()}] '
          'Conversation ended: ${event.conversationId} '
          '(${event.turnCount} turns, '
          '${event.totalTokens} tokens)',
        );
      },
      onCompaction: (event) async {
        log(
          '[${event.timestamp.toIso8601String()}] '
          'Compaction: ${event.messagesRemoved} messages removed, '
          '${event.tokensSaved} tokens saved',
        );
      },
    );
  }

  /// File backup lifecycle hooks.
  ///
  /// Creates backup copies of files before modifications.
  static ToolLifecycle fileBackup({
    required Future<void> Function(String path, String content) writeBackup,
    required Future<String?> Function(String path) readFile,
  }) {
    return ToolLifecycle(
      onToolBeforeExecution: (event) async {
        // Only intercept file-writing tools.
        final tool = event.toolName.toLowerCase();
        if (tool != 'write' && tool != 'edit') return null;

        final path =
            event.input['file_path'] as String? ??
            event.input['path'] as String?;
        if (path == null) return null;

        final content = await readFile(path);
        if (content != null) {
          await writeBackup('$path.bak', content);
        }

        return null; // Do not modify input.
      },
    );
  }

  /// Git safety lifecycle hooks.
  ///
  /// Checks for destructive git operations in bash commands and warns
  /// or blocks them.
  static ToolLifecycle gitSafety({
    List<String> protectedBranches = const ['main', 'master'],
    void Function(String warning)? onWarning,
  }) {
    final destructivePatterns = <RegExp>[
      RegExp(r'\bgit\s+push\s+.*--force\b'),
      RegExp(r'\bgit\s+push\s+-f\b'),
      RegExp(r'\bgit\s+reset\s+--hard\b'),
      RegExp(r'\bgit\s+clean\s+.*-f'),
      RegExp(r'\bgit\s+checkout\s+--\s+\.'),
      RegExp(r'\bgit\s+branch\s+(-d|-D)\s+'),
    ];

    return ToolLifecycle(
      onToolBeforeExecution: (event) async {
        if (event.toolName.toLowerCase() != 'bash') return null;

        final command = event.input['command'] as String? ?? '';

        for (final pattern in destructivePatterns) {
          if (pattern.hasMatch(command)) {
            // Check if targeting protected branch.
            for (final branch in protectedBranches) {
              if (command.contains(branch)) {
                onWarning?.call(
                  'Destructive git operation targeting protected '
                  'branch "$branch": $command',
                );
                // Return empty map to signal interception without modifying.
                return null;
              }
            }
            onWarning?.call('Destructive git operation detected: $command');
          }
        }
        return null;
      },
    );
  }

  /// Secret detection lifecycle hooks.
  ///
  /// Scans tool outputs for potential secrets (API keys, tokens, passwords)
  /// and emits warnings.
  static ToolLifecycle secretDetection({
    required void Function(String warning) onSecretFound,
  }) {
    final secretPatterns = <RegExp>[
      RegExp(r'(?:api[_-]?key|apikey)\s*[=:]\s*\S+', caseSensitive: false),
      RegExp(r'(?:password|passwd|pwd)\s*[=:]\s*\S+', caseSensitive: false),
      RegExp(r'(?:secret|token)\s*[=:]\s*\S+', caseSensitive: false),
      RegExp(
        r'(?:access[_-]?key|aws[_-]?key)\s*[=:]\s*\S+',
        caseSensitive: false,
      ),
      RegExp(r'-----BEGIN (?:RSA |DSA |EC )?PRIVATE KEY-----'),
      RegExp(r'sk-[a-zA-Z0-9]{20,}'),
      RegExp(r'ghp_[a-zA-Z0-9]{36}'),
    ];

    return ToolLifecycle(
      onToolAfterExecution: (event) async {
        final output = event.output;
        for (final pattern in secretPatterns) {
          if (pattern.hasMatch(output)) {
            onSecretFound(
              'Potential secret detected in output of '
              '"${event.toolName}": pattern ${pattern.pattern}',
            );
            break;
          }
        }
        return null; // Do not modify output.
      },
    );
  }

  /// Rate limiting lifecycle hooks.
  ///
  /// Tracks tool execution frequency and can throttle or warn when limits
  /// are approached.
  static ToolLifecycle rateLimiting({
    int maxToolCallsPerMinute = 120,
    void Function(String warning)? onLimitApproached,
    void Function(String error)? onLimitExceeded,
  }) {
    final callTimestamps = <DateTime>[];

    return ToolLifecycle(
      onToolBeforeExecution: (event) async {
        final now = DateTime.now();
        final windowStart = now.subtract(const Duration(minutes: 1));
        callTimestamps.removeWhere((t) => t.isBefore(windowStart));

        final count = callTimestamps.length;

        if (count >= maxToolCallsPerMinute) {
          onLimitExceeded?.call(
            'Tool call rate limit exceeded: '
            '$count/$maxToolCallsPerMinute per minute. '
            'Tool "${event.toolName}" may be throttled.',
          );
        } else if (count >= (maxToolCallsPerMinute * 0.8).round()) {
          onLimitApproached?.call(
            'Approaching tool call rate limit: '
            '$count/$maxToolCallsPerMinute per minute.',
          );
        }

        callTimestamps.add(now);
        return null; // Do not modify input.
      },
    );
  }

  /// Convenience method to register all built-in lifecycle hooks.
  static void registerAll(
    LifecycleManager manager, {
    void Function(int, int, double)? onCostUpdate,
    void Function(String)? logEntry,
    Future<void> Function(String, String)? writeBackup,
    Future<String?> Function(String)? readFile,
    List<String>? protectedBranches,
    void Function(String)? onGitWarning,
    void Function(String)? onSecretFound,
    int maxToolCallsPerMinute = 120,
    void Function(String)? onRateLimitWarning,
    void Function(String)? onRateLimitExceeded,
  }) {
    if (onCostUpdate != null) {
      manager.registerSession(costTracking(onCostUpdate: onCostUpdate));
    }

    if (logEntry != null) {
      manager.registerConversation(auditLog(log: logEntry));
    }

    if (writeBackup != null && readFile != null) {
      manager.registerTool(
        fileBackup(writeBackup: writeBackup, readFile: readFile),
      );
    }

    manager.registerTool(
      gitSafety(
        protectedBranches: protectedBranches ?? ['main', 'master'],
        onWarning: onGitWarning,
      ),
    );

    if (onSecretFound != null) {
      manager.registerTool(secretDetection(onSecretFound: onSecretFound));
    }

    manager.registerTool(
      rateLimiting(
        maxToolCallsPerMinute: maxToolCallsPerMinute,
        onLimitApproached: onRateLimitWarning,
        onLimitExceeded: onRateLimitExceeded,
      ),
    );
  }
}
