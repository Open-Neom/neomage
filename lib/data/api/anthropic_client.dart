import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';
import 'api_provider.dart';
import 'errors.dart';
import 'retry.dart';

/// Native Anthropic Messages API client with streaming support.
/// Direct port of neom_claw/src/services/api/claude.ts core functionality.
/// Includes retry logic with exponential backoff for transient errors.
class AnthropicClient extends ApiProvider {
  @override
  final ApiConfig config;

  /// Retry configuration for transient errors.
  final RetryConfig retryConfig;

  static const _apiVersion = '2023-06-01';
  static const _betaHeaders = 'tools-2024-04-04,prompt-caching-2024-07-31';

  /// Creates a client with the given Anthropic [config].
  ///
  /// Requires [config.apiKey] to be non-null.
  AnthropicClient(this.config, {this.retryConfig = RetryConfig.defaultConfig})
    : assert(config.apiKey != null);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'x-api-key': config.apiKey!,
    'anthropic-version': _apiVersion,
    'anthropic-beta': _betaHeaders,
    ...config.extraHeaders,
  };

  /// Stream a message completion via the Anthropic Messages API.
  @override
  Stream<StreamEvent> createMessageStream({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async* {
    final body = _buildRequestBody(
      messages: messages,
      systemPrompt: systemPrompt,
      tools: tools,
      maxTokens: maxTokens,
      stream: true,
    );

    final request = http.Request(
      'POST',
      Uri.parse('${config.baseUrl}/v1/messages'),
    );
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);

    final client = http.Client();
    final response = await client.send(request);

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      client.close();
      final classified = classifyApiError(
        statusCode: response.statusCode,
        body: errorBody,
        retryAfterHeader: response.headers['retry-after'],
      );
      yield ErrorEvent(message: classified.message, type: classified.type.name);
      return;
    }

    yield* _parseSSEStream(response.stream);
    client.close();
  }

  /// Send a non-streaming message completion with automatic retry.
  @override
  Future<Message> createMessage({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async {
    return withRetry(
      config: retryConfig,
      operation: (attempt) async {
        final body = _buildRequestBody(
          messages: messages,
          systemPrompt: systemPrompt,
          tools: tools,
          maxTokens: maxTokens,
          stream: false,
        );

        final response = await http.post(
          Uri.parse('${config.baseUrl}/v1/messages'),
          headers: _headers,
          body: jsonEncode(body),
        );

        if (response.statusCode != 200) {
          throw classifyApiError(
            statusCode: response.statusCode,
            body: response.body,
            retryAfterHeader: response.headers['retry-after'],
          );
        }

        return _parseMessageResponse(jsonDecode(response.body));
      },
    );
  }

  Map<String, dynamic> _buildRequestBody({
    required List<Message> messages,
    required String systemPrompt,
    required List<ToolDefinition> tools,
    int? maxTokens,
    required bool stream,
  }) {
    final body = <String, dynamic>{
      'model': config.model,
      'max_tokens': maxTokens ?? config.maxTokens,
      'system': [
        {'type': 'text', 'text': systemPrompt},
      ],
      'messages': messages.map((m) => m.toApiMap()).toList(),
      if (stream) 'stream': true,
    };

    if (tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toApiMap()).toList();
    }

    return body;
  }

  /// Parse Anthropic SSE stream into StreamEvents.
  Stream<StreamEvent> _parseSSEStream(http.ByteStream byteStream) async* {
    final lineStream = byteStream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    String? eventType;
    final dataBuffer = StringBuffer();

    await for (final line in lineStream) {
      if (line.startsWith('event: ')) {
        eventType = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        dataBuffer.write(line.substring(6));
      } else if (line.isEmpty && eventType != null) {
        final data = dataBuffer.toString();
        dataBuffer.clear();

        if (data.isNotEmpty) {
          final event = _parseEvent(eventType, jsonDecode(data));
          if (event != null) yield event;
        }
        eventType = null;
      }
    }
  }

  StreamEvent? _parseEvent(
    String type,
    Map<String, dynamic> data,
  ) => switch (type) {
    'message_start' => MessageStartEvent(
      messageId: data['message']?['id'] ?? '',
      model: data['message']?['model'] ?? config.model,
    ),
    'content_block_start' => ContentBlockStartEvent(
      index: data['index'] as int,
      block: _parseContentBlock(data['content_block']),
    ),
    'content_block_delta' => _parseDelta(data),
    'content_block_stop' => ContentBlockStopEvent(index: data['index'] as int),
    'message_delta' => MessageDeltaEvent(
      stopReason: _parseStopReason(data['delta']?['stop_reason']),
      usage: data['usage'] != null ? TokenUsage.fromJson(data['usage']) : null,
    ),
    'message_stop' => const MessageStopEvent(),
    'error' => ErrorEvent(
      message: data['error']?['message'] ?? 'Unknown error',
      type: data['error']?['type'],
    ),
    _ => null,
  };

  ContentBlockDeltaEvent? _parseDelta(Map<String, dynamic> data) {
    final delta = data['delta'] as Map<String, dynamic>?;
    if (delta == null) return null;

    final text =
        delta['text'] as String? ?? delta['partial_json'] as String? ?? '';

    return ContentBlockDeltaEvent(index: data['index'] as int, text: text);
  }

  ContentBlock _parseContentBlock(Map<String, dynamic>? block) {
    if (block == null) return const TextBlock('');
    return switch (block['type']) {
      'text' => TextBlock(block['text'] as String? ?? ''),
      'tool_use' => ToolUseBlock(
        id: block['id'] as String,
        name: block['name'] as String,
        input: (block['input'] as Map<String, dynamic>?) ?? {},
      ),
      _ => const TextBlock(''),
    };
  }

  StopReason? _parseStopReason(String? reason) => switch (reason) {
    'end_turn' => StopReason.endTurn,
    'max_tokens' => StopReason.maxTokens,
    'tool_use' => StopReason.toolUse,
    'stop_sequence' => StopReason.stopSequence,
    _ => null,
  };

  Message _parseMessageResponse(Map<String, dynamic> json) {
    final content = (json['content'] as List)
        .map((b) => _parseContentBlock(b as Map<String, dynamic>))
        .toList();

    return Message(
      id: json['id'] as String?,
      role: MessageRole.assistant,
      content: content,
      stopReason: _parseStopReason(json['stop_reason'] as String?),
      usage: json['usage'] != null ? TokenUsage.fromJson(json['usage']) : null,
    );
  }
}
