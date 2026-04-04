// Query engine — enhanced port of neom_claw/src/QueryEngine.ts.
// Implements the agentic loop with permission checking, compaction,
// session memory tracking, and thinking block support.

import 'dart:async';
import 'dart:convert';

import '../../domain/models/message.dart';
import '../../domain/models/permissions.dart';
import '../api/api_provider.dart';
import '../api/errors.dart';
import '../compact/compaction_service.dart';
import '../session/session_memory.dart';
import '../tools/tool.dart';
import '../tools/tool_registry.dart';

/// Callback for streaming text updates.
typedef OnTextDelta = void Function(String text);

/// Callback for tool execution events.
typedef OnToolUse = void Function(String toolName, Map<String, dynamic> input);
typedef OnToolResult = void Function(String toolName, ToolResult result);
typedef OnApiError = void Function(ApiError error);

/// Callback for permission prompts — returns true if allowed.
typedef OnPermissionRequest = Future<bool> Function(
  String toolName,
  Map<String, dynamic> input,
  PermissionExplanation? explanation,
);

/// Callback for compaction events.
typedef OnCompaction = void Function(CompactionResult result);

/// Configuration for the query engine.
class QueryEngineConfig {
  final int maxTurns;
  final int contextWindow;
  final bool enableCompaction;
  final bool enableMicrocompact;
  final bool enableSessionMemory;

  const QueryEngineConfig({
    this.maxTurns = 25,
    this.contextWindow = 200000,
    this.enableCompaction = true,
    this.enableMicrocompact = true,
    this.enableSessionMemory = true,
  });
}

/// Core conversation engine.
///
/// Implements the agentic loop:
///   user message → API call → tool extraction → permission check →
///   tool execution → result injection → compaction check → repeat
class QueryEngine {
  final ApiProvider provider;
  final ToolRegistry toolRegistry;
  final String systemPrompt;
  final QueryEngineConfig config;

  /// Optional compaction service.
  CompactionService? compactionService;

  /// Optional session memory service.
  SessionMemoryService? sessionMemory;

  /// Permission context for checking tool permissions.
  ToolPermissionContext? permissionContext;

  QueryEngine({
    required this.provider,
    required this.toolRegistry,
    required this.systemPrompt,
    this.config = const QueryEngineConfig(),
    this.compactionService,
    this.sessionMemory,
    this.permissionContext,
  });

  /// Run a full query with tool use loop (streaming).
  Future<Message> query({
    required List<Message> messages,
    OnTextDelta? onTextDelta,
    OnToolUse? onToolUse,
    OnToolResult? onToolResult,
    OnApiError? onError,
    OnPermissionRequest? onPermissionRequest,
    OnCompaction? onCompaction,
    void Function(StreamEvent)? onStreamEvent,
  }) async {
    var conversationMessages = List<Message>.from(messages);
    var turn = 0;

    while (turn < config.maxTurns) {
      turn++;

      // Phase 1: Microcompact old tool results before API call
      if (config.enableMicrocompact && compactionService != null) {
        conversationMessages =
            compactionService!.microcompact(conversationMessages);
      }

      // Phase 2: Auto-compact if approaching context limit
      if (config.enableCompaction && compactionService != null) {
        final compactionResult =
            await compactionService!.autoCompactIfNeeded(
          messages: conversationMessages,
          systemPrompt: systemPrompt,
          contextWindow: config.contextWindow,
        );
        if (compactionResult != null) {
          conversationMessages = compactionResult.compactedMessages;
          onCompaction?.call(compactionResult);
        }
      }

      // API call
      final assistantMessage = await _streamOneRound(
        messages: conversationMessages,
        onTextDelta: onTextDelta,
        onStreamEvent: onStreamEvent,
      );

      conversationMessages.add(assistantMessage);

      // Track for session memory
      sessionMemory?.trackMessage(assistantMessage);

      final toolUses = assistantMessage.toolUses;
      if (toolUses.isEmpty) {
        return assistantMessage;
      }

      // Execute all tool calls with permission checks
      final toolResults = <ContentBlock>[];
      for (final toolUse in toolUses) {
        final tool = toolRegistry.get(toolUse.name);

        // Permission check
        if (tool != null && onPermissionRequest != null) {
          final permResult = await _checkPermission(
            tool,
            toolUse.input,
            onPermissionRequest,
          );
          if (!permResult) {
            toolResults.add(ToolResultBlock(
              toolUseId: toolUse.id,
              content: 'Permission denied by user for ${toolUse.name}.',
              isError: true,
            ));
            continue;
          }
        }

        onToolUse?.call(toolUse.name, toolUse.input);

        final result =
            await toolRegistry.execute(toolUse.name, toolUse.input);

        onToolResult?.call(toolUse.name, result);

        toolResults.add(ToolResultBlock(
          toolUseId: toolUse.id,
          content: result.content,
          isError: result.isError,
        ));
      }

      final userMessage = Message(
        role: MessageRole.user,
        content: toolResults,
      );
      conversationMessages.add(userMessage);

      // Track tool results for session memory
      sessionMemory?.trackMessage(userMessage);
    }

    return Message.assistant(
        '[Max turns reached (${config.maxTurns}). Stopping tool use loop.]');
  }

  /// Check permission for a tool use.
  Future<bool> _checkPermission(
    Tool tool,
    Map<String, dynamic> input,
    OnPermissionRequest onPermissionRequest,
  ) async {
    // Read-only tools are auto-allowed
    if (tool.isReadOnly) return true;

    // Check tool's own permission logic
    if (permissionContext != null) {
      final decision =
          await tool.checkPermissions(input, permissionContext!);
      switch (decision) {
        case AllowDecision():
          return true;
        case DenyDecision():
          return false;
        case AskDecision():
          // Fall through to user prompt
          break;
      }
    }

    // Ask user
    final explanation = tool.getPermissionExplanation(input);
    return onPermissionRequest(tool.name, input, explanation);
  }

  Future<Message> _streamOneRound({
    required List<Message> messages,
    OnTextDelta? onTextDelta,
    void Function(StreamEvent)? onStreamEvent,
  }) async {
    final contentBlocks = <ContentBlock>[];
    final textBuffers = <int, StringBuffer>{};
    final toolUseBuffers = <int, _ToolUseBuildState>{};
    StopReason? stopReason;
    TokenUsage? usage;

    await for (final event in provider.createMessageStream(
      messages: messages,
      systemPrompt: systemPrompt,
      tools: toolRegistry.definitions,
    )) {
      onStreamEvent?.call(event);

      switch (event) {
        case ContentBlockStartEvent(index: final idx, block: final block):
          switch (block) {
            case TextBlock():
              textBuffers[idx] = StringBuffer();
            case ToolUseBlock(id: final id, name: final name):
              toolUseBuffers[idx] = _ToolUseBuildState(id: id, name: name);
            default:
              break;
          }

        case ContentBlockDeltaEvent(index: final idx, text: final text):
          if (textBuffers.containsKey(idx)) {
            textBuffers[idx]!.write(text);
            onTextDelta?.call(text);
          } else if (toolUseBuffers.containsKey(idx)) {
            toolUseBuffers[idx]!.jsonBuffer.write(text);
          }

        case ContentBlockStopEvent(index: final idx):
          if (textBuffers.containsKey(idx)) {
            final text = textBuffers[idx]!.toString();
            if (text.isNotEmpty) {
              contentBlocks.add(TextBlock(text));
            }
          } else if (toolUseBuffers.containsKey(idx)) {
            final state = toolUseBuffers[idx]!;
            contentBlocks.add(ToolUseBlock(
              id: state.id,
              name: state.name,
              input: state.parsedInput,
            ));
          }

        case MessageDeltaEvent(stopReason: final sr, usage: final u):
          stopReason = sr;
          usage = u;

        default:
          break;
      }
    }

    return Message(
      role: MessageRole.assistant,
      content: contentBlocks,
      stopReason: stopReason,
      usage: usage,
    );
  }
}

class _ToolUseBuildState {
  final String id;
  final String name;
  final StringBuffer jsonBuffer = StringBuffer();

  _ToolUseBuildState({required this.id, required this.name});

  Map<String, dynamic> get parsedInput {
    final json = jsonBuffer.toString().trim();
    if (json.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return {};
    }
  }
}
