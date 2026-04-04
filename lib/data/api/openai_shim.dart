import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';
import 'api_provider.dart';

const _uuid = Uuid();

/// OpenAI-compatible API shim — direct port of
/// neom_claw/src/services/api/openaiShim.ts
///
/// Translates Anthropic-format messages into OpenAI chat completion requests
/// and streams back events in the Anthropic streaming format so the rest
/// of the codebase is unaware of the underlying provider.
///
/// Supports: OpenAI, Azure OpenAI, Ollama, LM Studio, OpenRouter,
/// Together, Groq, Fireworks, DeepSeek, Mistral, and any OpenAI-compatible API.
class OpenAiShim extends ApiProvider {
  @override
  final ApiConfig config;

  OpenAiShim(this.config);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (config.apiKey != null) 'Authorization': 'Bearer ${config.apiKey}',
        ...config.extraHeaders,
      };

  // ── Anthropic → OpenAI message conversion ──

  /// Convert Anthropic system prompt to OpenAI system message.
  Map<String, dynamic> _systemMessage(String systemPrompt) => {
        'role': 'system',
        'content': systemPrompt,
      };

  /// Convert an Anthropic-format message to OpenAI format.
  Map<String, dynamic> _convertMessage(Message msg) {
    if (msg.role == MessageRole.user) {
      return _convertUserMessage(msg);
    }
    return _convertAssistantMessage(msg);
  }

  Map<String, dynamic> _convertUserMessage(Message msg) {
    final parts = <Map<String, dynamic>>[];

    for (final block in msg.content) {
      switch (block) {
        case TextBlock(text: final t):
          parts.add({'type': 'text', 'text': t});
        case ToolResultBlock(
            toolUseId: final tid,
            content: final c,
          ):
          // Tool results become separate tool messages in OpenAI
          return {'role': 'tool', 'content': c, 'tool_call_id': tid};
        case ImageBlock(mediaType: final m, base64Data: final d):
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:$m;base64,$d'},
          });
        default:
          break;
      }
    }

    // Check if all parts are tool results
    final toolResults = msg.content.whereType<ToolResultBlock>().toList();
    if (toolResults.isNotEmpty && toolResults.length == msg.content.length) {
      return {
        'role': 'tool',
        'content': toolResults.first.content,
        'tool_call_id': toolResults.first.toolUseId,
      };
    }

    if (parts.length == 1 && parts.first['type'] == 'text') {
      return {'role': 'user', 'content': parts.first['text']};
    }
    return {'role': 'user', 'content': parts};
  }

  Map<String, dynamic> _convertAssistantMessage(Message msg) {
    final textParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    for (final block in msg.content) {
      switch (block) {
        case TextBlock(text: final t):
          textParts.add(t);
        case ToolUseBlock(id: final id, name: final n, input: final i):
          toolCalls.add({
            'id': id,
            'type': 'function',
            'function': {'name': n, 'arguments': jsonEncode(i)},
          });
        default:
          break;
      }
    }

    return {
      'role': 'assistant',
      'content': textParts.join('\n'),
      if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
    };
  }

  /// Expand messages with multiple tool results into separate messages.
  List<Map<String, dynamic>> _expandMessages(
    List<Message> messages,
    String systemPrompt,
  ) {
    final result = <Map<String, dynamic>>[_systemMessage(systemPrompt)];

    for (final msg in messages) {
      if (msg.role == MessageRole.user) {
        final toolResults = msg.content.whereType<ToolResultBlock>().toList();
        final otherContent =
            msg.content.where((b) => b is! ToolResultBlock).toList();

        // Add tool results as separate messages
        for (final tr in toolResults) {
          result.add({
            'role': 'tool',
            'content': tr.content,
            'tool_call_id': tr.toolUseId,
          });
        }

        // Add remaining content as user message
        if (otherContent.isNotEmpty) {
          result.add(_convertMessage(Message(
            role: MessageRole.user,
            content: otherContent,
          )));
        }
      } else {
        result.add(_convertMessage(msg));
      }
    }

    return result;
  }

  // ── OpenAI → Anthropic event conversion ──

  @override
  Stream<StreamEvent> createMessageStream({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async* {
    final openAiMessages = _expandMessages(messages, systemPrompt);

    final body = <String, dynamic>{
      'model': config.model,
      'messages': openAiMessages,
      'stream': true,
      'max_tokens': maxTokens ?? config.maxTokens,
    };

    if (tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toOpenAiMap()).toList();
    }

    final request = http.Request(
      'POST',
      Uri.parse('${config.baseUrl}/chat/completions'),
    );
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);

    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      yield ErrorEvent(
        message: 'OpenAI API error ${response.statusCode}: $errorBody',
        type: 'api_error',
      );
      return;
    }

    // Emit synthetic Anthropic-format events from OpenAI stream
    final messageId = 'msg_${_uuid.v4()}';
    yield MessageStartEvent(messageId: messageId, model: config.model);

    var currentIndex = 0;
    var hasStartedText = false;
    final toolCallBuffers = <int, _ToolCallBuffer>{};

    await for (final event
        in _parseOpenAiSSE(response.stream)) {
      final choices = event['choices'] as List?;
      if (choices == null || choices.isEmpty) continue;

      final delta = choices[0]['delta'] as Map<String, dynamic>?;
      if (delta == null) continue;

      // Handle text content
      final content = delta['content'] as String?;
      if (content != null && content.isNotEmpty) {
        if (!hasStartedText) {
          yield ContentBlockStartEvent(
            index: currentIndex,
            block: const TextBlock(''),
          );
          hasStartedText = true;
        }
        yield ContentBlockDeltaEvent(index: currentIndex, text: content);
      }

      // Handle tool calls
      final toolCalls = delta['tool_calls'] as List?;
      if (toolCalls != null) {
        for (final tc in toolCalls) {
          final tcMap = tc as Map<String, dynamic>;
          final tcIndex = tcMap['index'] as int;

          if (!toolCallBuffers.containsKey(tcIndex)) {
            // Close text block if open
            if (hasStartedText) {
              yield ContentBlockStopEvent(index: currentIndex);
              currentIndex++;
              hasStartedText = false;
            }

            toolCallBuffers[tcIndex] = _ToolCallBuffer(
              id: tcMap['id'] as String? ?? 'call_${_uuid.v4()}',
              name: (tcMap['function']
                  as Map<String, dynamic>?)?['name'] as String? ?? '',
              argumentsBuffer: StringBuffer(),
            );

            yield ContentBlockStartEvent(
              index: currentIndex + tcIndex,
              block: ToolUseBlock(
                id: toolCallBuffers[tcIndex]!.id,
                name: toolCallBuffers[tcIndex]!.name,
                input: {},
              ),
            );
          }

          final args = (tcMap['function']
              as Map<String, dynamic>?)?['arguments'] as String?;
          if (args != null) {
            toolCallBuffers[tcIndex]!.argumentsBuffer.write(args);
            yield ContentBlockDeltaEvent(
              index: currentIndex + tcIndex,
              text: args,
            );
          }
        }
      }

      // Handle finish
      final finishReason = choices[0]['finish_reason'] as String?;
      if (finishReason != null) {
        if (hasStartedText) {
          yield ContentBlockStopEvent(index: currentIndex);
        }
        for (final tcIndex in toolCallBuffers.keys) {
          yield ContentBlockStopEvent(index: currentIndex + tcIndex);
        }

        final stopReason = switch (finishReason) {
          'stop' => StopReason.endTurn,
          'length' => StopReason.maxTokens,
          'tool_calls' => StopReason.toolUse,
          _ => StopReason.endTurn,
        };

        final usage = event['usage'] as Map<String, dynamic>?;
        yield MessageDeltaEvent(
          stopReason: stopReason,
          usage: usage != null
              ? TokenUsage(
                  inputTokens: usage['prompt_tokens'] as int? ?? 0,
                  outputTokens: usage['completion_tokens'] as int? ?? 0,
                )
              : null,
        );
        yield const MessageStopEvent();
      }
    }
  }

  @override
  Future<Message> createMessage({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async {
    final openAiMessages = _expandMessages(messages, systemPrompt);

    final body = <String, dynamic>{
      'model': config.model,
      'messages': openAiMessages,
      'max_tokens': maxTokens ?? config.maxTokens,
    };

    if (tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toOpenAiMap()).toList();
    }

    final response = await http.post(
      Uri.parse('${config.baseUrl}/chat/completions'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'OpenAI API error ${response.statusCode}: ${response.body}');
    }

    return _parseOpenAiResponse(jsonDecode(response.body));
  }

  Message _parseOpenAiResponse(Map<String, dynamic> json) {
    final choice = (json['choices'] as List).first as Map<String, dynamic>;
    final msg = choice['message'] as Map<String, dynamic>;
    final content = <ContentBlock>[];

    final text = msg['content'] as String?;
    if (text != null && text.isNotEmpty) {
      content.add(TextBlock(text));
    }

    final toolCalls = msg['tool_calls'] as List?;
    if (toolCalls != null) {
      for (final tc in toolCalls) {
        final tcMap = tc as Map<String, dynamic>;
        final fn = tcMap['function'] as Map<String, dynamic>;
        content.add(ToolUseBlock(
          id: tcMap['id'] as String,
          name: fn['name'] as String,
          input: jsonDecode(fn['arguments'] as String),
        ));
      }
    }

    return Message(
      role: MessageRole.assistant,
      content: content,
      stopReason: switch (choice['finish_reason']) {
        'stop' => StopReason.endTurn,
        'length' => StopReason.maxTokens,
        'tool_calls' => StopReason.toolUse,
        _ => StopReason.endTurn,
      },
      usage: json['usage'] != null
          ? TokenUsage(
              inputTokens: json['usage']['prompt_tokens'] as int? ?? 0,
              outputTokens:
                  json['usage']['completion_tokens'] as int? ?? 0,
            )
          : null,
    );
  }

  /// Parse OpenAI SSE stream.
  Stream<Map<String, dynamic>> _parseOpenAiSSE(
    http.ByteStream byteStream,
  ) async* {
    await for (final line
        in byteStream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data == '[DONE]') return;
        try {
          yield jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          // Skip malformed JSON
        }
      }
    }
  }
}

class _ToolCallBuffer {
  final String id;
  final String name;
  final StringBuffer argumentsBuffer;

  _ToolCallBuffer({
    required this.id,
    required this.name,
    required this.argumentsBuffer,
  });
}
