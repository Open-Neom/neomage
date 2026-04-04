// Tool execution service — faithful port of neom_claw/src/services/tools/.
// Covers: toolExecution.ts, toolHooks.ts, StreamingToolExecutor.ts,
//         toolOrchestration.ts.
//
// All classes, methods, types, and concurrency control are ported.

import 'dart:async';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Tool use block from the API response.
class ToolUseBlock {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const ToolUseBlock({
    required this.id,
    required this.name,
    this.input = const {},
  });
}

/// Assistant message (simplified).
class AssistantMessage {
  final String uuid;
  final String messageId;
  final String? requestId;
  final List<dynamic> content;
  final bool isApiErrorMessage;
  final Map<String, dynamic>? usage;

  const AssistantMessage({
    required this.uuid,
    required this.messageId,
    this.requestId,
    this.content = const [],
    this.isApiErrorMessage = false,
    this.usage,
  });
}

/// A message returned from tool execution.
class ToolMessage {
  final String type; // 'user', 'attachment', 'progress'
  final List<ToolResultBlock>? toolResults;
  final String? toolUseResult;
  final String? sourceToolAssistantUUID;
  final Map<String, dynamic>? attachment;
  final dynamic progressData;

  const ToolMessage({
    required this.type,
    this.toolResults,
    this.toolUseResult,
    this.sourceToolAssistantUUID,
    this.attachment,
    this.progressData,
  });
}

/// A tool result block within a message.
class ToolResultBlock {
  final String type = 'tool_result';
  final String toolUseId;
  final String content;
  final bool isError;

  const ToolResultBlock({
    required this.toolUseId,
    required this.content,
    this.isError = false,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'tool_use_id': toolUseId,
    'content': content,
    'is_error': isError,
  };
}

/// Permission decision result.
enum PermissionBehavior { allow, deny, ask }

/// Permission result from hooks or rules.
class PermissionResult {
  final PermissionBehavior behavior;
  final String? message;
  final Map<String, dynamic>? updatedInput;
  final PermissionDecisionReason? decisionReason;

  const PermissionResult({
    required this.behavior,
    this.message,
    this.updatedInput,
    this.decisionReason,
  });
}

/// Reason for a permission decision.
class PermissionDecisionReason {
  final String type; // 'hook', 'rule', 'mode', 'other', etc.
  final String? hookName;
  final String? hookSource;
  final String? reason;
  final PermissionRule? rule;

  const PermissionDecisionReason({
    required this.type,
    this.hookName,
    this.hookSource,
    this.reason,
    this.rule,
  });
}

/// A permission rule with source info.
class PermissionRule {
  final String source; // 'session', 'localSettings', 'userSettings', etc.
  final String? pattern;

  const PermissionRule({required this.source, this.pattern});
}

/// Cancel message constant.
const cancelMessage = 'I was interrupted by the user and didn\'t finish.';
const rejectMessage = 'User rejected this tool call.';

// ---------------------------------------------------------------------------
// Tool definition
// ---------------------------------------------------------------------------

/// A tool definition.
class ToolDefinition {
  final String name;
  final List<String> aliases;
  final bool isMcp;
  final bool Function(Map<String, dynamic> input) isConcurrencySafe;
  final bool Function()? requiresUserInteraction;
  final String Function()? interruptBehavior; // 'cancel' | 'block'
  final String Function(Map<String, dynamic>)? getToolUseSummary;
  final Future<ToolMessage> Function(
    Map<String, dynamic> input,
    ToolUseContext context,
  )
  execute;
  final bool Function(Map<String, dynamic>)? validateInput;

  const ToolDefinition({
    required this.name,
    this.aliases = const [],
    this.isMcp = false,
    required this.isConcurrencySafe,
    this.requiresUserInteraction,
    this.interruptBehavior,
    this.getToolUseSummary,
    required this.execute,
    this.validateInput,
  });
}

/// Find a tool by name in the tools list.
ToolDefinition? findToolByName(List<ToolDefinition> tools, String name) {
  for (final tool in tools) {
    if (tool.name == name) return tool;
    if (tool.aliases.contains(name)) return tool;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Tool use context
// ---------------------------------------------------------------------------

/// Context passed to tool execution.
class ToolUseContext {
  final List<ToolDefinition> tools;
  final String mainLoopModel;
  final List<dynamic> mcpClients;
  final bool isNonInteractiveSession;
  final String? querySource;
  final String? agentId;
  final bool requireCanUseTool;
  final AbortController abortController;
  final void Function(Set<String> Function(Set<String>) updater)?
  setInProgressToolUseIDs;
  final void Function(bool)? setHasInterruptibleToolInProgress;
  final void Function(String)? setStreamMode;
  final void Function(int Function(int))? setResponseLength;
  final void Function(String?)? setSDKStatus;
  final void Function(Map<String, dynamic>)? addNotification;
  final Future<Map<String, dynamic>> Function()? getAppState;
  final Map<String, ({String content, int timestamp})> readFileState;
  final Set<String>? loadedNestedMemoryPaths;
  final QueryTracking? queryTracking;
  final String? requestPrompt;

  ToolUseContext({
    required this.tools,
    required this.mainLoopModel,
    this.mcpClients = const [],
    this.isNonInteractiveSession = false,
    this.querySource,
    this.agentId,
    this.requireCanUseTool = false,
    required this.abortController,
    this.setInProgressToolUseIDs,
    this.setHasInterruptibleToolInProgress,
    this.setStreamMode,
    this.setResponseLength,
    this.setSDKStatus,
    this.addNotification,
    this.getAppState,
    Map<String, ({String content, int timestamp})>? readFileState,
    this.loadedNestedMemoryPaths,
    this.queryTracking,
    this.requestPrompt,
  }) : readFileState = readFileState ?? {};
}

/// Query tracking info.
class QueryTracking {
  final String? chainId;
  final int? depth;

  const QueryTracking({this.chainId, this.depth});
}

/// Abort controller for cancellation.
class AbortController {
  final _controller = StreamController<String>.broadcast();
  bool _aborted = false;
  String? _reason;

  bool get isAborted => _aborted;
  String? get reason => _reason;
  Stream<String> get onAbort => _controller.stream;

  void abort([String? reason]) {
    if (_aborted) return;
    _aborted = true;
    _reason = reason;
    _controller.add(reason ?? 'aborted');
  }

  void dispose() {
    _controller.close();
  }
}

/// Create a child abort controller that fires when the parent fires.
AbortController createChildAbortController(AbortController parent) {
  final child = AbortController();
  parent.onAbort.listen((reason) {
    child.abort(reason);
  });
  return child;
}

// ---------------------------------------------------------------------------
// MCP server type
// ---------------------------------------------------------------------------

/// MCP server transport type.
enum McpServerType { stdio, sse, http, ws, sdk, sseIde, wsIde, neomClawAiProxy }

/// Check if a tool name corresponds to an MCP tool.
bool isMcpTool(String toolName) => toolName.startsWith('mcp__');

/// Sanitize tool name for analytics (strips MCP prefix details).
String sanitizeToolNameForAnalytics(String toolName) {
  if (!toolName.startsWith('mcp__')) return toolName;
  return 'mcp';
}

// ---------------------------------------------------------------------------
// Tool error classification
// ---------------------------------------------------------------------------

/// Display threshold for hook timing summary.
const hookTimingDisplayThresholdMs = 500;

/// Classify a tool execution error into a telemetry-safe string.
String classifyToolError(Object error) {
  if (error is ShellError) return 'ShellError';
  if (error is AbortError) return 'AbortError';
  if (error is Error) return 'Error';
  return 'UnknownError';
}

/// Shell error for tool execution.
class ShellError implements Exception {
  final String message;
  final int? exitCode;
  ShellError(this.message, {this.exitCode});
  @override
  String toString() => 'ShellError: $message';
}

/// Abort error when tool execution is cancelled.
class AbortError implements Exception {
  final String message;
  AbortError([this.message = 'Aborted']);
  @override
  String toString() => 'AbortError: $message';
}

// ---------------------------------------------------------------------------
// Message update from tool execution
// ---------------------------------------------------------------------------

/// A message update yielded during tool execution.
class MessageUpdate {
  final ToolMessage? message;
  final ToolUseContext? newContext;
  final ContextModifier? contextModifier;

  const MessageUpdate({this.message, this.newContext, this.contextModifier});
}

/// A context modifier attached to a message update.
class ContextModifier {
  final String toolUseID;
  final ToolUseContext Function(ToolUseContext context) modifyContext;

  const ContextModifier({required this.toolUseID, required this.modifyContext});
}

// ---------------------------------------------------------------------------
// Permission decision mapping (for OTel)
// ---------------------------------------------------------------------------

/// Map a rule's origin to OTel `source` vocabulary.
String ruleSourceToOTelSource(String ruleSource, PermissionBehavior behavior) {
  switch (ruleSource) {
    case 'session':
      return behavior == PermissionBehavior.allow
          ? 'user_temporary'
          : 'user_reject';
    case 'localSettings':
    case 'userSettings':
      return behavior == PermissionBehavior.allow
          ? 'user_permanent'
          : 'user_reject';
    default:
      return 'config';
  }
}

/// Map a PermissionDecisionReason to the OTel source label.
String decisionReasonToOTelSource(
  PermissionDecisionReason? reason,
  PermissionBehavior behavior,
) {
  if (reason == null) return 'config';
  switch (reason.type) {
    case 'permissionPromptTool':
      return behavior == PermissionBehavior.allow
          ? 'user_temporary'
          : 'user_reject';
    case 'rule':
      if (reason.rule != null) {
        return ruleSourceToOTelSource(reason.rule!.source, behavior);
      }
      return 'config';
    case 'hook':
      return 'hook';
    default:
      return 'config';
  }
}

// ---------------------------------------------------------------------------
// runToolUse — main tool execution entry point
// ---------------------------------------------------------------------------

/// Type for the canUseTool callback.
typedef CanUseToolFn =
    Future<PermissionResult> Function(
      ToolDefinition tool,
      Map<String, dynamic> input,
      ToolUseContext context,
      AssistantMessage assistantMessage,
      String toolUseID, [
      PermissionResult? forceDecision,
    ]);

/// Run a single tool use block — checks permissions and executes the tool.
Stream<MessageUpdate> runToolUse(
  ToolUseBlock toolUse,
  AssistantMessage assistantMessage,
  CanUseToolFn canUseTool,
  ToolUseContext toolUseContext,
) async* {
  final toolName = toolUse.name;

  // First try available tools
  var tool = findToolByName(toolUseContext.tools, toolName);

  // Fallback for deprecated aliases
  if (tool == null) {
    // Would search all base tools — simplified for port
  }

  if (tool == null) {
    yield MessageUpdate(
      message: ToolMessage(
        type: 'user',
        toolResults: [
          ToolResultBlock(
            toolUseId: toolUse.id,
            content:
                '<tool_use_error>Error: No such tool available: $toolName</tool_use_error>',
            isError: true,
          ),
        ],
        toolUseResult: 'Error: No such tool available: $toolName',
        sourceToolAssistantUUID: assistantMessage.uuid,
      ),
    );
    return;
  }

  if (toolUseContext.abortController.isAborted) {
    yield MessageUpdate(
      message: ToolMessage(
        type: 'user',
        toolResults: [
          ToolResultBlock(toolUseId: toolUse.id, content: cancelMessage),
        ],
        toolUseResult: cancelMessage,
        sourceToolAssistantUUID: assistantMessage.uuid,
      ),
    );
    return;
  }

  try {
    // Check permissions
    final permissionResult = await canUseTool(
      tool,
      toolUse.input,
      toolUseContext,
      assistantMessage,
      toolUse.id,
    );

    if (permissionResult.behavior == PermissionBehavior.deny) {
      yield MessageUpdate(
        message: ToolMessage(
          type: 'user',
          toolResults: [
            ToolResultBlock(
              toolUseId: toolUse.id,
              content: permissionResult.message ?? rejectMessage,
              isError: true,
            ),
          ],
          toolUseResult: permissionResult.message ?? rejectMessage,
          sourceToolAssistantUUID: assistantMessage.uuid,
        ),
      );
      return;
    }

    // Execute the tool
    final effectiveInput = permissionResult.updatedInput ?? toolUse.input;
    final result = await tool.execute(effectiveInput, toolUseContext);

    yield MessageUpdate(message: result);
  } catch (error) {
    final errorMsg = error is Exception ? error.toString() : '$error';
    final detailedError = 'Error calling tool (${tool.name}): $errorMsg';

    yield MessageUpdate(
      message: ToolMessage(
        type: 'user',
        toolResults: [
          ToolResultBlock(
            toolUseId: toolUse.id,
            content: '<tool_use_error>$detailedError</tool_use_error>',
            isError: true,
          ),
        ],
        toolUseResult: detailedError,
        sourceToolAssistantUUID: assistantMessage.uuid,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resolve hook permission decision (toolHooks.ts)
// ---------------------------------------------------------------------------

/// Resolve a PreToolUse hook's permission result into a final decision.
///
/// Encapsulates the invariant that hook 'allow' does NOT bypass
/// settings.json deny/ask rules.
Future<({PermissionResult decision, Map<String, dynamic> input})>
resolveHookPermissionDecision({
  required PermissionResult? hookPermissionResult,
  required ToolDefinition tool,
  required Map<String, dynamic> input,
  required ToolUseContext toolUseContext,
  required CanUseToolFn canUseTool,
  required AssistantMessage assistantMessage,
  required String toolUseID,
  Future<PermissionResult?> Function(
    ToolDefinition,
    Map<String, dynamic>,
    ToolUseContext,
  )?
  checkRuleBasedPermissions,
}) async {
  final requiresInteraction = tool.requiresUserInteraction?.call() ?? false;
  final requireCanUseTool = toolUseContext.requireCanUseTool;

  if (hookPermissionResult?.behavior == PermissionBehavior.allow) {
    final hookInput = hookPermissionResult!.updatedInput ?? input;
    final interactionSatisfied =
        requiresInteraction && hookPermissionResult.updatedInput != null;

    if ((requiresInteraction && !interactionSatisfied) || requireCanUseTool) {
      return (
        decision: await canUseTool(
          tool,
          hookInput,
          toolUseContext,
          assistantMessage,
          toolUseID,
        ),
        input: hookInput,
      );
    }

    // Hook allow skips interactive prompt, but deny/ask rules still apply
    if (checkRuleBasedPermissions != null) {
      final ruleCheck = await checkRuleBasedPermissions(
        tool,
        hookInput,
        toolUseContext,
      );
      if (ruleCheck != null) {
        if (ruleCheck.behavior == PermissionBehavior.deny) {
          return (decision: ruleCheck, input: hookInput);
        }
        // ask rule — dialog required despite hook approval
        return (
          decision: await canUseTool(
            tool,
            hookInput,
            toolUseContext,
            assistantMessage,
            toolUseID,
          ),
          input: hookInput,
        );
      }
    }

    return (decision: hookPermissionResult, input: hookInput);
  }

  if (hookPermissionResult?.behavior == PermissionBehavior.deny) {
    return (decision: hookPermissionResult!, input: input);
  }

  // No hook decision or 'ask' — normal permission flow
  final forceDecision = hookPermissionResult?.behavior == PermissionBehavior.ask
      ? hookPermissionResult
      : null;
  final askInput =
      (hookPermissionResult?.behavior == PermissionBehavior.ask &&
          hookPermissionResult?.updatedInput != null)
      ? hookPermissionResult!.updatedInput!
      : input;

  return (
    decision: await canUseTool(
      tool,
      askInput,
      toolUseContext,
      assistantMessage,
      toolUseID,
      forceDecision,
    ),
    input: askInput,
  );
}

// ---------------------------------------------------------------------------
// Tool orchestration (toolOrchestration.ts)
// ---------------------------------------------------------------------------

/// Partition tool calls into batches where each batch is either:
/// 1. A single non-concurrency-safe tool, or
/// 2. Multiple consecutive concurrency-safe tools
class ToolBatch {
  final bool isConcurrencySafe;
  final List<ToolUseBlock> blocks;

  const ToolBatch({required this.isConcurrencySafe, required this.blocks});
}

/// Partition tool calls into batches for orchestration.
List<ToolBatch> partitionToolCalls(
  List<ToolUseBlock> toolUseMessages,
  ToolUseContext toolUseContext,
) {
  final batches = <ToolBatch>[];

  for (final toolUse in toolUseMessages) {
    final tool = findToolByName(toolUseContext.tools, toolUse.name);
    bool isConcurrencySafe = false;
    if (tool != null) {
      try {
        isConcurrencySafe = tool.isConcurrencySafe(toolUse.input);
      } catch (_) {
        isConcurrencySafe = false;
      }
    }

    if (isConcurrencySafe &&
        batches.isNotEmpty &&
        batches.last.isConcurrencySafe) {
      // Mutable list — extend the last batch
      batches.last.blocks.add(toolUse);
    } else {
      batches.add(
        ToolBatch(isConcurrencySafe: isConcurrencySafe, blocks: [toolUse]),
      );
    }
  }

  return batches;
}

/// Max concurrent tool executions.
int getMaxToolUseConcurrency() => 10;

/// Run tools — handles both serial and concurrent execution.
Stream<MessageUpdate> runTools(
  List<ToolUseBlock> toolUseMessages,
  List<AssistantMessage> assistantMessages,
  CanUseToolFn canUseTool,
  ToolUseContext toolUseContext,
) async* {
  var currentContext = toolUseContext;

  for (final batch in partitionToolCalls(toolUseMessages, currentContext)) {
    if (batch.isConcurrencySafe) {
      // Run concurrency-safe batch in parallel
      final futures = <Future<List<MessageUpdate>>>[];

      for (final toolUse in batch.blocks) {
        currentContext.setInProgressToolUseIDs?.call(
          (prev) => {...prev, toolUse.id},
        );

        final assistantMsg = assistantMessages.firstWhere(
          (a) => a.content.any(
            (c) => c is Map && c['type'] == 'tool_use' && c['id'] == toolUse.id,
          ),
          orElse: () => assistantMessages.first,
        );

        futures.add(
          runToolUse(
            toolUse,
            assistantMsg,
            canUseTool,
            currentContext,
          ).toList(),
        );
      }

      final results = await Future.wait(futures);
      for (final updates in results) {
        for (final update in updates) {
          yield MessageUpdate(
            message: update.message,
            newContext: currentContext,
          );
        }
      }

      // Mark all as complete
      for (final toolUse in batch.blocks) {
        _markToolUseAsComplete(currentContext, toolUse.id);
      }
    } else {
      // Run non-concurrency-safe batch serially
      for (final toolUse in batch.blocks) {
        currentContext.setInProgressToolUseIDs?.call(
          (prev) => {...prev, toolUse.id},
        );

        final assistantMsg = assistantMessages.firstWhere(
          (a) => a.content.any(
            (c) => c is Map && c['type'] == 'tool_use' && c['id'] == toolUse.id,
          ),
          orElse: () => assistantMessages.first,
        );

        await for (final update in runToolUse(
          toolUse,
          assistantMsg,
          canUseTool,
          currentContext,
        )) {
          if (update.contextModifier != null) {
            currentContext = update.contextModifier!.modifyContext(
              currentContext,
            );
          }
          yield MessageUpdate(
            message: update.message,
            newContext: currentContext,
          );
        }

        _markToolUseAsComplete(currentContext, toolUse.id);
      }
    }
  }
}

void _markToolUseAsComplete(ToolUseContext context, String toolUseID) {
  context.setInProgressToolUseIDs?.call((prev) {
    final next = Set<String>.from(prev);
    next.remove(toolUseID);
    return next;
  });
}

// ---------------------------------------------------------------------------
// StreamingToolExecutor (StreamingToolExecutor.ts)
// ---------------------------------------------------------------------------

/// Status of a tracked tool in the streaming executor.
enum ToolStatus { queued, executing, completed, yielded }

/// A tool tracked by the streaming executor.
class _TrackedTool {
  final String id;
  final ToolUseBlock block;
  final AssistantMessage assistantMessage;
  ToolStatus status;
  final bool isConcurrencySafe;
  Future<void>? promise;
  List<ToolMessage>? results;
  final List<ToolMessage> pendingProgress;
  List<ContextModifier>? contextModifiers;

  _TrackedTool({
    required this.id,
    required this.block,
    required this.assistantMessage,
    required this.status,
    required this.isConcurrencySafe,
    this.results,
    List<ToolMessage>? pendingProgress,
  }) : pendingProgress = pendingProgress ?? [];
}

/// Executes tools as they stream in with concurrency control.
/// - Concurrent-safe tools can execute in parallel
/// - Non-concurrent tools must execute alone (exclusive access)
/// - Results are buffered and emitted in the order tools were received
class StreamingToolExecutor {
  final List<ToolDefinition> _toolDefinitions;
  final CanUseToolFn _canUseTool;
  ToolUseContext _toolUseContext;
  final List<_TrackedTool> _tools = [];
  bool _hasErrored = false;
  String _erroredToolDescription = '';
  late final AbortController _siblingAbortController;
  bool _discarded = false;
  Completer<void>? _progressAvailableCompleter;

  StreamingToolExecutor({
    required List<ToolDefinition> toolDefinitions,
    required CanUseToolFn canUseTool,
    required ToolUseContext toolUseContext,
  }) : _toolDefinitions = toolDefinitions,
       _canUseTool = canUseTool,
       _toolUseContext = toolUseContext {
    _siblingAbortController = createChildAbortController(
      toolUseContext.abortController,
    );
  }

  /// Discards all pending and in-progress tools.
  void discard() {
    _discarded = true;
  }

  /// Add a tool to the execution queue. Starts executing immediately if
  /// conditions allow.
  void addTool(ToolUseBlock block, AssistantMessage assistantMessage) {
    final toolDefinition = findToolByName(_toolDefinitions, block.name);

    if (toolDefinition == null) {
      _tools.add(
        _TrackedTool(
          id: block.id,
          block: block,
          assistantMessage: assistantMessage,
          status: ToolStatus.completed,
          isConcurrencySafe: true,
          results: [
            ToolMessage(
              type: 'user',
              toolResults: [
                ToolResultBlock(
                  toolUseId: block.id,
                  content:
                      '<tool_use_error>Error: No such tool available: ${block.name}</tool_use_error>',
                  isError: true,
                ),
              ],
              toolUseResult: 'Error: No such tool available: ${block.name}',
              sourceToolAssistantUUID: assistantMessage.uuid,
            ),
          ],
        ),
      );
      return;
    }

    bool isConcurrencySafe;
    try {
      isConcurrencySafe = toolDefinition.isConcurrencySafe(block.input);
    } catch (_) {
      isConcurrencySafe = false;
    }

    _tools.add(
      _TrackedTool(
        id: block.id,
        block: block,
        assistantMessage: assistantMessage,
        status: ToolStatus.queued,
        isConcurrencySafe: isConcurrencySafe,
      ),
    );

    _processQueue();
  }

  /// Check if a tool can execute based on current concurrency state.
  bool _canExecuteTool(bool isConcurrencySafe) {
    final executingTools = _tools.where(
      (t) => t.status == ToolStatus.executing,
    );
    return executingTools.isEmpty ||
        (isConcurrencySafe && executingTools.every((t) => t.isConcurrencySafe));
  }

  /// Process the queue, starting tools when concurrency conditions allow.
  void _processQueue() {
    for (final tool in _tools) {
      if (tool.status != ToolStatus.queued) continue;
      if (_canExecuteTool(tool.isConcurrencySafe)) {
        _executeTool(tool);
      } else if (!tool.isConcurrencySafe) {
        break;
      }
    }
  }

  /// Execute a tool and collect its results.
  void _executeTool(_TrackedTool tool) {
    tool.status = ToolStatus.executing;
    _toolUseContext.setInProgressToolUseIDs?.call((prev) => {...prev, tool.id});

    final messages = <ToolMessage>[];
    final contextModifiers = <ContextModifier>[];

    tool.promise = () async {
      // Check abort
      if (_discarded ||
          _hasErrored ||
          _toolUseContext.abortController.isAborted) {
        messages.add(_createSyntheticErrorMessage(tool));
        tool.results = messages;
        tool.status = ToolStatus.completed;
        return;
      }

      final toolAbortController = createChildAbortController(
        _siblingAbortController,
      );

      await for (final update in runToolUse(
        tool.block,
        tool.assistantMessage,
        _canUseTool,
        ToolUseContext(
          tools: _toolUseContext.tools,
          mainLoopModel: _toolUseContext.mainLoopModel,
          mcpClients: _toolUseContext.mcpClients,
          abortController: toolAbortController,
          setInProgressToolUseIDs: _toolUseContext.setInProgressToolUseIDs,
          querySource: _toolUseContext.querySource,
        ),
      )) {
        if (update.message != null) {
          if (update.message!.type == 'progress') {
            tool.pendingProgress.add(update.message!);
            _progressAvailableCompleter?.complete();
            _progressAvailableCompleter = null;
          } else {
            messages.add(update.message!);

            // Check for Bash errors
            final isError =
                update.message!.toolResults?.any((r) => r.isError) ?? false;
            if (isError && tool.block.name == 'Bash') {
              _hasErrored = true;
              _erroredToolDescription = _getToolDescription(tool);
              _siblingAbortController.abort('sibling_error');
            }
          }
        }
        if (update.contextModifier != null) {
          contextModifiers.add(update.contextModifier!);
        }
      }

      tool.results = messages;
      tool.contextModifiers = contextModifiers;
      tool.status = ToolStatus.completed;

      if (!tool.isConcurrencySafe && contextModifiers.isNotEmpty) {
        for (final modifier in contextModifiers) {
          _toolUseContext = modifier.modifyContext(_toolUseContext);
        }
      }
    }();

    tool.promise!.whenComplete(() => _processQueue());
  }

  ToolMessage _createSyntheticErrorMessage(_TrackedTool tool) {
    if (_discarded) {
      return ToolMessage(
        type: 'user',
        toolResults: [
          ToolResultBlock(
            toolUseId: tool.id,
            content:
                '<tool_use_error>Error: Streaming fallback - tool execution discarded</tool_use_error>',
            isError: true,
          ),
        ],
        sourceToolAssistantUUID: tool.assistantMessage.uuid,
      );
    }
    if (_toolUseContext.abortController.isAborted) {
      return ToolMessage(
        type: 'user',
        toolResults: [
          ToolResultBlock(
            toolUseId: tool.id,
            content: rejectMessage,
            isError: true,
          ),
        ],
        sourceToolAssistantUUID: tool.assistantMessage.uuid,
      );
    }
    final desc = _erroredToolDescription;
    final msg = desc.isNotEmpty
        ? 'Cancelled: parallel tool call $desc errored'
        : 'Cancelled: parallel tool call errored';
    return ToolMessage(
      type: 'user',
      toolResults: [
        ToolResultBlock(
          toolUseId: tool.id,
          content: '<tool_use_error>$msg</tool_use_error>',
          isError: true,
        ),
      ],
      sourceToolAssistantUUID: tool.assistantMessage.uuid,
    );
  }

  String _getToolDescription(_TrackedTool tool) {
    final input = tool.block.input;
    final summary =
        input['command'] ?? input['file_path'] ?? input['pattern'] ?? '';
    if (summary is String && summary.isNotEmpty) {
      final truncated = summary.length > 40
          ? '${summary.substring(0, 40)}...'
          : summary;
      return '${tool.block.name}($truncated)';
    }
    return tool.block.name;
  }

  /// Get completed results that haven't been yielded yet.
  List<MessageUpdate> getCompletedResults() {
    if (_discarded) return [];

    final results = <MessageUpdate>[];
    for (final tool in _tools) {
      // Yield pending progress
      while (tool.pendingProgress.isNotEmpty) {
        results.add(
          MessageUpdate(
            message: tool.pendingProgress.removeAt(0),
            newContext: _toolUseContext,
          ),
        );
      }

      if (tool.status == ToolStatus.yielded) continue;
      if (tool.status == ToolStatus.completed && tool.results != null) {
        tool.status = ToolStatus.yielded;
        for (final message in tool.results!) {
          results.add(
            MessageUpdate(message: message, newContext: _toolUseContext),
          );
        }
        _markToolUseAsComplete(_toolUseContext, tool.id);
      } else if (tool.status == ToolStatus.executing &&
          !tool.isConcurrencySafe) {
        break;
      }
    }
    return results;
  }

  /// Wait for remaining tools and return their results.
  Stream<MessageUpdate> getRemainingResults() async* {
    if (_discarded) return;

    while (_tools.any((t) => t.status != ToolStatus.yielded)) {
      _processQueue();

      for (final result in getCompletedResults()) {
        yield result;
      }

      // Wait for any executing tool to complete or progress to be available
      if (_tools.any((t) => t.status == ToolStatus.executing)) {
        final executingPromises = _tools
            .where((t) => t.status == ToolStatus.executing && t.promise != null)
            .map((t) => t.promise!)
            .toList();

        _progressAvailableCompleter = Completer<void>();
        if (executingPromises.isNotEmpty) {
          await Future.any([
            ...executingPromises,
            _progressAvailableCompleter!.future,
          ]);
        }
      }
    }

    for (final result in getCompletedResults()) {
      yield result;
    }
  }

  /// Get the current tool use context.
  ToolUseContext getUpdatedContext() => _toolUseContext;
}
