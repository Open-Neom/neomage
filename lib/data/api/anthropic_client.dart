import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sint_sentinel/sint_sentinel_core.dart';

import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';
import '../../utils/security/neomage_network_guard.dart';
import 'api_provider.dart';
import 'errors.dart';
import 'retry.dart';

/// Native Anthropic Messages API client with streaming support.
/// Direct port of neomage/src/services/api/claude.ts core functionality.
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

  static const int _maxErrorBodyBytes = 512 * 1024;
  static const int _maxResponseBytes = 16 * 1024 * 1024;
  static const int _maxSseEventChars = 8 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 120);

  Map<String, String> get _headers {
    final sanitizedExtra = <String, String>{};
    for (final entry in config.extraHeaders.entries) {
      if (!NeomageNetworkGuard.isValidHeaderName(entry.key)) continue;
      sanitizedExtra[entry.key] = NeomageNetworkGuard.sanitizeHeaderValue(
        entry.value,
      );
    }
    return {
      'Content-Type': 'application/json',
      'x-api-key': NeomageNetworkGuard.sanitizeHeaderValue(config.apiKey ?? ''),
      'anthropic-version': _apiVersion,
      'anthropic-beta': _betaHeaders,
      ...sanitizedExtra,
    };
  }

  Uri? _buildMessagesUri() {
    var base = config.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.tryParse('$base/v1/messages');
    if (!NeomageNetworkGuard.isSafeEndpointUri(
      uri,
      allowLoopbackInsecure: true,
      secureSchemes: const <String>{'https'},
      insecureSchemes: const <String>{'http'},
    )) {
      return null;
    }
    return uri;
  }

  Future<String> _readBoundedUtf8(
    Stream<List<int>> byteStream,
    int maxBytes,
  ) async {
    final chunks = <int>[];
    await for (final chunk in byteStream) {
      final remaining = maxBytes - chunks.length;
      if (remaining <= 0) break;
      if (chunk.length <= remaining) {
        chunks.addAll(chunk);
      } else {
        chunks.addAll(chunk.sublist(0, remaining));
        break;
      }
    }
    return utf8.decode(chunks, allowMalformed: true);
  }

  /// Stream a message completion via the Anthropic Messages API.
  @override
  Stream<StreamEvent> createMessageStream({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async* {
    final uri = _buildMessagesUri();
    if (uri == null) {
      yield const ErrorEvent(
        message: 'Blocked unsafe Anthropic baseUrl',
        type: 'invalid_request_error',
      );
      return;
    }

    final body = _buildRequestBody(
      messages: messages,
      systemPrompt: systemPrompt,
      tools: tools,
      maxTokens: maxTokens,
      stream: true,
    );

    final safeUrlLog = NeomageNetworkGuard.redactUrlCredentials(uri.toString());
    final maskedKey = NeomageNetworkGuard.maskApiKey(config.apiKey);
    SintSentinel.logger.d(
      'AnthropicClient.createMessageStream: POST $safeUrlLog (key: $maskedKey)',
    );

    final request = http.Request('POST', uri)..followRedirects = false;
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final response = await SintSentinel.guard(
        () => client.send(request).timeout(_requestTimeout),
        tag: 'AnthropicClient.createMessageStream',
      );

      SintSentinel.logger.d(
        'AnthropicClient response status: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        final errorBody = await _readBoundedUtf8(
          response.stream,
          _maxErrorBodyBytes,
        );
        final redactedError = NeomageNetworkGuard.sanitizeApiErrorBody(
          errorBody,
        );
        SintSentinel.logger.e(
          'AnthropicClient API error ${response.statusCode}: $redactedError',
        );
        final classified = classifyApiError(
          statusCode: response.statusCode,
          body: errorBody,
          retryAfterHeader: response.headers['retry-after'],
        );
        yield ErrorEvent(
          message: NeomageNetworkGuard.redactTransportError(classified.message),
          type: classified.type.name,
        );
        return;
      }

      yield* _parseSSEStream(response.stream);
    } finally {
      client.close();
    }
  }

  /// Send a non-streaming message completion with automatic retry.
  @override
  Future<Message> createMessage({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async {
    final uri = _buildMessagesUri();
    if (uri == null) {
      throw ArgumentError('Blocked unsafe Anthropic baseUrl');
    }

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

        final safeUrlLog = NeomageNetworkGuard.redactUrlCredentials(
          uri.toString(),
        );
        SintSentinel.logger.d(
          'AnthropicClient.createMessage: POST $safeUrlLog (attempt: $attempt)',
        );

        final client = http.Client();
        try {
          final request = http.Request('POST', uri)..followRedirects = false;
          request.headers.addAll(_headers);
          request.body = jsonEncode(body);

          final streamed = await SintSentinel.guard(
            () => client.send(request).timeout(_requestTimeout),
            tag: 'AnthropicClient.createMessage',
          );
          final responseBody = await _readBoundedUtf8(
            streamed.stream,
            _maxResponseBytes,
          );

          SintSentinel.logger.d(
            'AnthropicClient.createMessage response: ${streamed.statusCode}',
          );

          if (streamed.statusCode != 200) {
            final redacted = NeomageNetworkGuard.sanitizeApiErrorBody(
              responseBody,
            );
            SintSentinel.logger.e(
              'AnthropicClient API error ${streamed.statusCode}: $redacted',
            );
            throw classifyApiError(
              statusCode: streamed.statusCode,
              body: responseBody,
              retryAfterHeader: streamed.headers['retry-after'],
            );
          }

          return _parseMessageResponse(
            jsonDecode(responseBody) as Map<String, dynamic>,
          );
        } finally {
          client.close();
        }
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
        {
          'type': 'text',
          'text': systemPrompt,
          'cache_control': {'type': 'ephemeral'},
        },
      ],
      'messages': messages.map((m) => m.toApiMap()).toList(),
      if (stream) 'stream': true,
    };

    if (tools.isNotEmpty) {
      // Sort tools alphabetically for deterministic ordering — ensures
      // Anthropic's server-side prompt cache hits across requests even
      // when tools are registered in different order.
      final sorted = List<ToolDefinition>.from(tools)
        ..sort((a, b) => a.name.compareTo(b.name));

      // Mark the last tool with cache_control so the entire prefix
      // (system prompt + tools) is cached server-side by Anthropic.
      final toolMaps = sorted.map((t) => t.toApiMap()).toList();
      if (toolMaps.isNotEmpty) {
        toolMaps.last['cache_control'] = {'type': 'ephemeral'};
      }
      body['tools'] = toolMaps;
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
    var overflowed = false;

    await for (final line in lineStream) {
      if (line.length > _maxSseEventChars) {
        overflowed = true;
        continue;
      }
      if (line.startsWith('event: ')) {
        eventType = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        if (overflowed) continue;
        final chunk = line.substring(6);
        if (dataBuffer.length + chunk.length > _maxSseEventChars) {
          overflowed = true;
          dataBuffer.clear();
          continue;
        }
        dataBuffer.write(chunk);
      } else if (line.isEmpty && eventType != null) {
        if (overflowed) {
          dataBuffer.clear();
          eventType = null;
          overflowed = false;
          yield const ErrorEvent(
            message: 'SSE event exceeded maximum allowed size',
            type: 'overloaded_error',
          );
          continue;
        }
        final data = dataBuffer.toString();
        dataBuffer.clear();

        if (data.isNotEmpty) {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map<String, dynamic>) {
              final event = _parseEvent(eventType, decoded);
              if (event != null) yield event;
            }
          } catch (_) {
            // Skip malformed SSE JSON frames.
          }
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
