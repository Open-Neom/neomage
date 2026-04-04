// ConversationEngine — port of neom_claw/src/services/conversation/.
// Core agentic loop: message → API → tool use → result → repeat.

import 'dart:async';
import 'dart:convert';

import '../api/api_provider.dart';
import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';

// ─── Types ───

/// Turn in a conversation.
class ConversationTurn {
  final Message userMessage;
  final Message assistantMessage;
  final List<ToolExecution> toolExecutions;
  final Duration duration;
  final int inputTokens;
  final int outputTokens;
  final double cost;
  final int turnIndex;

  const ConversationTurn({
    required this.userMessage,
    required this.assistantMessage,
    required this.toolExecutions,
    required this.duration,
    required this.inputTokens,
    required this.outputTokens,
    required this.cost,
    required this.turnIndex,
  });
}

/// Record of a tool execution within a turn.
class ToolExecution {
  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> input;
  final String output;
  final bool isError;
  final Duration duration;
  final bool permissionGranted;
  final String? permissionRule;

  const ToolExecution({
    required this.toolName,
    required this.toolUseId,
    required this.input,
    required this.output,
    this.isError = false,
    required this.duration,
    this.permissionGranted = true,
    this.permissionRule,
  });
}

/// Conversation state.
enum ConversationState {
  idle,
  sendingMessage,
  streaming,
  executingTool,
  waitingPermission,
  compacting,
  error,
}

/// Events emitted during conversation processing.
sealed class ConversationEvent {
  const ConversationEvent();
}

class StateChanged extends ConversationEvent {
  final ConversationState state;
  const StateChanged(this.state);
}

class StreamingText extends ConversationEvent {
  final String text;
  const StreamingText(this.text);
}

class StreamingThinking extends ConversationEvent {
  final String text;
  const StreamingThinking(this.text);
}

class ToolUseRequested extends ConversationEvent {
  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> input;
  const ToolUseRequested(this.toolName, this.toolUseId, this.input);
}

class ToolExecutionStarted extends ConversationEvent {
  final String toolName;
  final String toolUseId;
  const ToolExecutionStarted(this.toolName, this.toolUseId);
}

class ToolExecutionCompleted extends ConversationEvent {
  final ToolExecution execution;
  const ToolExecutionCompleted(this.execution);
}

class PermissionNeeded extends ConversationEvent {
  final String toolName;
  final Map<String, dynamic> input;
  final Completer<PermissionDecision> completer;
  const PermissionNeeded(this.toolName, this.input, this.completer);
}

class TurnCompleted extends ConversationEvent {
  final ConversationTurn turn;
  const TurnCompleted(this.turn);
}

class ConversationError extends ConversationEvent {
  final Object error;
  final StackTrace? stackTrace;
  const ConversationError(this.error, [this.stackTrace]);
}

class TokenUsageUpdated extends ConversationEvent {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  const TokenUsageUpdated(
    this.inputTokens,
    this.outputTokens,
    this.cacheReadTokens,
    this.cacheCreationTokens,
  );
}

/// Permission decision from user.
enum PermissionDecision { allow, allowAlways, deny }

/// Permission checker callback.
typedef PermissionChecker =
    Future<PermissionDecision> Function(
      String toolName,
      Map<String, dynamic> input,
      String? description,
    );

/// Configuration for the conversation engine.
class ConversationConfig {
  final String model;
  final String? systemPrompt;
  final int maxTurns;
  final int maxTokens;
  final bool enableThinking;
  final int? thinkingBudget;
  final bool enableCaching;
  final List<int> cacheBreakpoints;
  final Duration toolTimeout;
  final bool planMode;
  final List<String>? allowedTools;
  final Map<String, String>? toolAliases;

  const ConversationConfig({
    required this.model,
    this.systemPrompt,
    this.maxTurns = 100,
    this.maxTokens = 16000,
    this.enableThinking = false,
    this.thinkingBudget,
    this.enableCaching = true,
    this.cacheBreakpoints = const [],
    this.toolTimeout = const Duration(minutes: 2),
    this.planMode = false,
    this.allowedTools,
    this.toolAliases,
  });

  ConversationConfig copyWith({
    String? model,
    String? systemPrompt,
    int? maxTurns,
    int? maxTokens,
    bool? enableThinking,
    int? thinkingBudget,
    bool? enableCaching,
    List<int>? cacheBreakpoints,
    Duration? toolTimeout,
    bool? planMode,
    List<String>? allowedTools,
  }) {
    return ConversationConfig(
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      maxTurns: maxTurns ?? this.maxTurns,
      maxTokens: maxTokens ?? this.maxTokens,
      enableThinking: enableThinking ?? this.enableThinking,
      thinkingBudget: thinkingBudget ?? this.thinkingBudget,
      enableCaching: enableCaching ?? this.enableCaching,
      cacheBreakpoints: cacheBreakpoints ?? this.cacheBreakpoints,
      toolTimeout: toolTimeout ?? this.toolTimeout,
      planMode: planMode ?? this.planMode,
      allowedTools: allowedTools ?? this.allowedTools,
    );
  }
}

// ─── Engine ───

/// Core conversation engine — manages the agentic loop.
class ConversationEngine {
  final ApiProvider _provider;
  final ToolRegistry _toolRegistry;
  final PermissionChecker _permissionChecker;
  ConversationConfig _config;

  final List<Map<String, dynamic>> _messages = [];
  final List<ConversationTurn> _turns = [];
  final StreamController<ConversationEvent> _events =
      StreamController.broadcast();

  ConversationState _state = ConversationState.idle;
  bool _cancelled = false;

  // Token tracking
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;
  int _totalCacheReadTokens = 0;
  int _totalCacheCreationTokens = 0;

  ConversationEngine({
    required ApiProvider provider,
    required ToolRegistry toolRegistry,
    required PermissionChecker permissionChecker,
    required ConversationConfig config,
  }) : _provider = provider,
       _toolRegistry = toolRegistry,
       _permissionChecker = permissionChecker,
       _config = config;

  /// Event stream for UI updates.
  Stream<ConversationEvent> get events => _events.stream;

  /// Current state.
  ConversationState get state => _state;

  /// All turns so far.
  List<ConversationTurn> get turns => List.unmodifiable(_turns);

  /// Total token usage.
  int get totalInputTokens => _totalInputTokens;
  int get totalOutputTokens => _totalOutputTokens;

  /// Raw message history (for serialization).
  List<Map<String, dynamic>> get messages => List.unmodifiable(_messages);

  /// Update configuration.
  void updateConfig(ConversationConfig config) {
    _config = config;
  }

  /// Load previous messages (for session restore).
  void loadMessages(List<Map<String, dynamic>> messages) {
    _messages.clear();
    _messages.addAll(messages);
  }

  /// Cancel the current operation.
  void cancel() {
    _cancelled = true;
  }

  /// Send a user message and run the agentic loop.
  Future<ConversationTurn> sendMessage(
    String text, {
    List<Map<String, dynamic>>? attachments,
  }) async {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    // Build user message
    final userContent = <Map<String, dynamic>>[];
    if (text.isNotEmpty) {
      userContent.add({'type': 'text', 'text': text});
    }
    if (attachments != null) {
      userContent.addAll(attachments);
    }

    final userMsg = {'role': 'user', 'content': userContent};
    _messages.add(userMsg);

    final toolExecutions = <ToolExecution>[];
    int turnInputTokens = 0;
    int turnOutputTokens = 0;

    try {
      _setState(ConversationState.streaming);

      // Agentic loop — keep calling API until no more tool_use
      var loopCount = 0;
      while (loopCount < _config.maxTurns && !_cancelled) {
        loopCount++;

        // Build API request
        final request = _buildRequest();

        // Stream the response
        final response = await _streamResponse(request);
        turnInputTokens += response.inputTokens;
        turnOutputTokens += response.outputTokens;

        // Add assistant message to history
        _messages.add({'role': 'assistant', 'content': response.contentBlocks});

        // Check if there are tool_use blocks
        final toolUseBlocks = response.contentBlocks
            .where((b) => b['type'] == 'tool_use')
            .toList();

        if (toolUseBlocks.isEmpty || response.stopReason != 'tool_use') {
          // No more tool calls — turn is complete
          break;
        }

        // Execute tools
        _setState(ConversationState.executingTool);
        final toolResults = <Map<String, dynamic>>[];

        for (final toolBlock in toolUseBlocks) {
          if (_cancelled) break;

          final toolName = toolBlock['name'] as String;
          final toolId = toolBlock['id'] as String;
          final toolInput = toolBlock['input'] as Map<String, dynamic>? ?? {};

          _events.add(ToolUseRequested(toolName, toolId, toolInput));

          // Check permission
          final permitted = await _checkPermission(toolName, toolInput);
          if (!permitted) {
            toolResults.add({
              'type': 'tool_result',
              'tool_use_id': toolId,
              'content': 'Permission denied by user.',
              'is_error': true,
            });
            toolExecutions.add(
              ToolExecution(
                toolName: toolName,
                toolUseId: toolId,
                input: toolInput,
                output: 'Permission denied by user.',
                isError: true,
                duration: Duration.zero,
                permissionGranted: false,
              ),
            );
            continue;
          }

          // Execute the tool
          _events.add(ToolExecutionStarted(toolName, toolId));
          final execStopwatch = Stopwatch()..start();

          try {
            final resolvedName = _config.toolAliases?[toolName] ?? toolName;
            final tool = _toolRegistry.get(resolvedName);

            String result;
            bool isError = false;

            if (tool != null) {
              final output = await tool
                  .execute(toolInput)
                  .timeout(_config.toolTimeout);
              result = output.content;
            } else {
              result = 'Tool "$toolName" not found.';
              isError = true;
            }

            execStopwatch.stop();

            // Truncate very long outputs
            if (result.length > 100000) {
              result =
                  '${result.substring(0, 100000)}\n\n[Output truncated — ${result.length} chars total]';
            }

            toolResults.add({
              'type': 'tool_result',
              'tool_use_id': toolId,
              'content': result,
              if (isError) 'is_error': true,
            });

            final execution = ToolExecution(
              toolName: toolName,
              toolUseId: toolId,
              input: toolInput,
              output: result,
              isError: isError,
              duration: execStopwatch.elapsed,
              permissionGranted: true,
            );
            toolExecutions.add(execution);
            _events.add(ToolExecutionCompleted(execution));
          } on TimeoutException {
            execStopwatch.stop();
            toolResults.add({
              'type': 'tool_result',
              'tool_use_id': toolId,
              'content':
                  'Tool execution timed out after ${_config.toolTimeout.inSeconds}s.',
              'is_error': true,
            });
            toolExecutions.add(
              ToolExecution(
                toolName: toolName,
                toolUseId: toolId,
                input: toolInput,
                output: 'Timeout',
                isError: true,
                duration: execStopwatch.elapsed,
              ),
            );
          } catch (e) {
            execStopwatch.stop();
            toolResults.add({
              'type': 'tool_result',
              'tool_use_id': toolId,
              'content': 'Error: $e',
              'is_error': true,
            });
            toolExecutions.add(
              ToolExecution(
                toolName: toolName,
                toolUseId: toolId,
                input: toolInput,
                output: 'Error: $e',
                isError: true,
                duration: execStopwatch.elapsed,
              ),
            );
          }
        }

        // Add tool results as user message
        _messages.add({'role': 'user', 'content': toolResults});

        // Continue the loop (next API call will see tool results)
        _setState(ConversationState.streaming);
      }

      stopwatch.stop();

      // Build turn summary
      final userMessage = Message(
        role: MessageRole.user,
        content: [TextBlock(text)],
      );
      final assistantText = _extractAssistantText();
      final assistantMessage = Message(
        role: MessageRole.assistant,
        content: [TextBlock(assistantText)],
      );

      final turn = ConversationTurn(
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        toolExecutions: toolExecutions,
        duration: stopwatch.elapsed,
        inputTokens: turnInputTokens,
        outputTokens: turnOutputTokens,
        cost: _estimateCost(turnInputTokens, turnOutputTokens),
        turnIndex: _turns.length,
      );

      _turns.add(turn);
      _totalInputTokens += turnInputTokens;
      _totalOutputTokens += turnOutputTokens;

      _events.add(
        TokenUsageUpdated(
          _totalInputTokens,
          _totalOutputTokens,
          _totalCacheReadTokens,
          _totalCacheCreationTokens,
        ),
      );
      _events.add(TurnCompleted(turn));
      _setState(ConversationState.idle);

      return turn;
    } catch (e, st) {
      stopwatch.stop();
      _events.add(ConversationError(e, st));
      _setState(ConversationState.error);
      rethrow;
    }
  }

  /// Build the API request payload.
  Map<String, dynamic> _buildRequest() {
    final toolDefs = _getToolDefinitions();

    final request = <String, dynamic>{
      'model': _config.model,
      'max_tokens': _config.maxTokens,
      'messages': _messages,
      if (_config.systemPrompt != null) 'system': _config.systemPrompt,
      if (toolDefs.isNotEmpty) 'tools': toolDefs,
      'stream': true,
    };

    if (_config.enableThinking) {
      request['thinking'] = {
        'type': 'enabled',
        if (_config.thinkingBudget != null)
          'budget_tokens': _config.thinkingBudget,
      };
    }

    return request;
  }

  /// Get tool definitions for the API.
  List<Map<String, dynamic>> _getToolDefinitions() {
    final tools = _toolRegistry.all.toList();
    final allowed = _config.allowedTools;

    return tools
        .where((t) => allowed == null || allowed.contains(t.name))
        .map(
          (t) => ToolDefinition(
            name: t.name,
            description: t.description,
            inputSchema: t.inputSchema,
          ).toApiMap(),
        )
        .toList();
  }

  /// Stream a response from the API.
  Future<_StreamResult> _streamResponse(Map<String, dynamic> request) async {
    final contentBlocks = <Map<String, dynamic>>[];
    int inputTokens = 0;
    int outputTokens = 0;
    String? stopReason;

    // Use the provider's streaming capabilities
    final messages = request['messages'] as List<dynamic>? ?? [];
    final systemPrompt = request['system'] as String? ?? '';
    final stream = _provider.createMessageStream(
      messages: messages.cast(),
      systemPrompt: systemPrompt,
      maxTokens: request['max_tokens'] as int?,
    );

    final textBuffer = StringBuffer();
    final _thinkingBuffer = StringBuffer();
    final accumulators = <int, Map<String, dynamic>>{};
    var blockIndex = 0;

    await for (final event in stream) {
      if (_cancelled) break;

      if (event is MessageStartEvent) {
        // MessageStartEvent only has messageId and model.
        // Token usage comes from MessageDeltaEvent.
      } else if (event is ContentBlockStartEvent) {
        blockIndex = event.index;
        // Convert ContentBlock to a mutable map for accumulation.
        final block = event.block;
        final Map<String, dynamic> blockMap;
        switch (block) {
          case TextBlock():
            blockMap = {'type': 'text', 'text': ''};
          case ToolUseBlock(:final id, :final name, :final input):
            blockMap = {
              'type': 'tool_use',
              'id': id,
              'name': name,
              'input': input,
            };
          case ToolResultBlock():
            blockMap = {'type': 'tool_result'};
          case ImageBlock():
            blockMap = {'type': 'image'};
        }
        accumulators[blockIndex] = blockMap;
      } else if (event is ContentBlockDeltaEvent) {
        final acc = accumulators[event.index];
        if (acc != null) {
          if (acc['type'] == 'text') {
            final delta = event.text;
            textBuffer.write(delta);
            acc['text'] = textBuffer.toString();
            _events.add(StreamingText(delta));
          } else if (acc['type'] == 'tool_use') {
            // For tool_use blocks, delta text is partial JSON.
            acc['_partial_json'] =
                (acc['_partial_json'] as String? ?? '') + event.text;
          }
        }
      } else if (event is ContentBlockStopEvent) {
        final acc = accumulators[event.index];
        if (acc != null) {
          if (acc['type'] == 'tool_use' && acc['_partial_json'] != null) {
            try {
              acc['input'] = jsonDecode(acc['_partial_json'] as String);
            } catch (_) {
              acc['input'] = <String, dynamic>{};
            }
            acc.remove('_partial_json');
          }
          contentBlocks.add(acc);
        }
      } else if (event is MessageDeltaEvent) {
        stopReason = switch (event.stopReason) {
          StopReason.endTurn => 'end_turn',
          StopReason.maxTokens => 'max_tokens',
          StopReason.toolUse => 'tool_use',
          StopReason.stopSequence => 'stop_sequence',
          null => null,
        };
        outputTokens = event.usage?.outputTokens ?? outputTokens;
        inputTokens = event.usage?.inputTokens ?? inputTokens;
      }
    }

    return _StreamResult(
      contentBlocks: contentBlocks,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      stopReason: stopReason ?? 'end_turn',
    );
  }

  /// Check permission for a tool call.
  Future<bool> _checkPermission(
    String toolName,
    Map<String, dynamic> input,
  ) async {
    // Some tools are always allowed
    const alwaysAllowed = {
      'Read',
      'Glob',
      'Grep',
      'ToolSearch',
      'TodoWrite',
      'TaskOutput',
    };
    if (alwaysAllowed.contains(toolName)) return true;

    _setState(ConversationState.waitingPermission);
    final decision = await _permissionChecker(
      toolName,
      input,
      input['description'] as String?,
    );
    _setState(ConversationState.executingTool);

    return decision == PermissionDecision.allow ||
        decision == PermissionDecision.allowAlways;
  }

  /// Extract text from the last assistant message.
  String _extractAssistantText() {
    if (_messages.isEmpty) return '';
    final last = _messages.last;
    if (last['role'] != 'assistant') return '';
    final content = last['content'];
    if (content is String) return content;
    if (content is List) {
      final texts = content
          .whereType<Map<String, dynamic>>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String? ?? '')
          .toList();
      return texts.join();
    }
    return '';
  }

  /// Estimate cost for a given token usage.
  double _estimateCost(int input, int output) {
    // Simplified pricing — real implementation uses model_catalog
    final model = _config.model;
    double inputPrice, outputPrice; // per million tokens
    if (model.contains('opus')) {
      inputPrice = 15.0;
      outputPrice = 75.0;
    } else if (model.contains('sonnet')) {
      inputPrice = 3.0;
      outputPrice = 15.0;
    } else if (model.contains('haiku')) {
      inputPrice = 0.25;
      outputPrice = 1.25;
    } else if (model.contains('gpt-4o-mini')) {
      inputPrice = 0.15;
      outputPrice = 0.6;
    } else if (model.contains('gpt-4o')) {
      inputPrice = 2.5;
      outputPrice = 10.0;
    } else {
      inputPrice = 3.0;
      outputPrice = 15.0;
    }
    return (input * inputPrice + output * outputPrice) / 1000000;
  }

  void _setState(ConversationState newState) {
    _state = newState;
    _events.add(StateChanged(newState));
  }

  /// Get total cost.
  double get totalCost => _estimateCost(_totalInputTokens, _totalOutputTokens);

  /// Clear conversation history.
  void clear() {
    _messages.clear();
    _turns.clear();
    _totalInputTokens = 0;
    _totalOutputTokens = 0;
    _totalCacheReadTokens = 0;
    _totalCacheCreationTokens = 0;
    _setState(ConversationState.idle);
  }

  /// Compact conversation (replace old messages with summary).
  Future<void> compact(String summary) async {
    _setState(ConversationState.compacting);
    _messages.clear();
    _messages.add({
      'role': 'user',
      'content': [
        {
          'type': 'text',
          'text':
              '[Conversation compacted. Summary of previous context:]\n\n$summary',
        },
      ],
    });
    _messages.add({
      'role': 'assistant',
      'content': [
        {
          'type': 'text',
          'text':
              'I understand. I have the context from the conversation summary. How can I continue helping you?',
        },
      ],
    });
    _setState(ConversationState.idle);
  }

  /// Dispose resources.
  void dispose() {
    _events.close();
  }
}

/// Internal result of streaming an API response.
class _StreamResult {
  final List<Map<String, dynamic>> contentBlocks;
  final int inputTokens;
  final int outputTokens;
  final String stopReason;

  const _StreamResult({
    required this.contentBlocks,
    required this.inputTokens,
    required this.outputTokens,
    required this.stopReason,
  });
}

// ─── Tool execution helpers ───

/// Execute a tool with timeout and error handling.
Future<ToolResult> executeToolSafe(
  Tool tool,
  Map<String, dynamic> input, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  try {
    return await tool.execute(input).timeout(timeout);
  } on TimeoutException {
    return ToolResult.error(
      'Tool execution timed out after ${timeout.inSeconds}s.',
    );
  } catch (e) {
    return ToolResult.error('$e');
  }
}

/// Format a tool result for display.
String formatToolResult(ToolExecution execution) {
  final buffer = StringBuffer();
  buffer.writeln('Tool: ${execution.toolName}');
  buffer.writeln('Duration: ${execution.duration.inMilliseconds}ms');
  if (execution.isError) {
    buffer.writeln('Status: ERROR');
  } else {
    buffer.writeln('Status: OK');
  }
  buffer.writeln('Output:');
  buffer.writeln(execution.output);
  return buffer.toString();
}

/// Check if a stop reason indicates the model wants to use tools.
bool isToolUseStop(String stopReason) => stopReason == 'tool_use';

/// Check if a stop reason indicates natural completion.
bool isNaturalStop(String stopReason) =>
    stopReason == 'end_turn' || stopReason == 'stop_sequence';

/// Check if we've exceeded the turn limit.
bool hasExceededTurnLimit(int turns, int maxTurns) => turns >= maxTurns;

/// Build a system prompt with context.
String buildSystemPromptWithContext({
  required String basePrompt,
  String? memoryContent,
  String? projectInfo,
  List<String>? activeTools,
  bool planMode = false,
}) {
  final buffer = StringBuffer(basePrompt);

  if (memoryContent != null && memoryContent.isNotEmpty) {
    buffer.writeln('\n\n<memory>\n$memoryContent\n</memory>');
  }

  if (projectInfo != null && projectInfo.isNotEmpty) {
    buffer.writeln('\n\n<project_info>\n$projectInfo\n</project_info>');
  }

  if (activeTools != null && activeTools.isNotEmpty) {
    buffer.writeln('\n\nAvailable tools: ${activeTools.join(", ")}');
  }

  if (planMode) {
    buffer.writeln(
      '\n\nYou are currently in PLAN MODE. '
      'Analyze the request and create a detailed plan. '
      'Do not execute any changes yet — only plan.',
    );
  }

  return buffer.toString();
}
