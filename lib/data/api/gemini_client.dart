import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sint_sentinel/sint_sentinel_core.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';
import '../../utils/security/neomage_network_guard.dart';
import 'api_provider.dart';

const _uuid = Uuid();
const int _maxErrorBodyBytes = 512 * 1024;
const int _maxResponseBytes = 16 * 1024 * 1024;
const int _maxSseLineChars = 4 * 1024 * 1024;
const Duration _requestTimeout = Duration(seconds: 120);
final RegExp _safeModelNameRegex = RegExp(r'^[A-Za-z0-9._\-]{1,128}$');

Future<String> _readBoundedUtf8(Stream<List<int>> stream, int maxBytes) async {
  final chunks = <int>[];
  await for (final chunk in stream) {
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

/// Native Google Gemini API client with SSE streaming support.
///
/// Unlike OpenAI-compatible providers, the Gemini REST API uses a completely
/// different authentication scheme (query-parameter API key instead of Bearer
/// token), endpoint layout (`/models/{model}:streamGenerateContent`), and
/// message format (`contents` / `parts` instead of `messages`).
///
/// This client translates the app's internal [Message] model into Gemini's
/// request format and converts Gemini's SSE responses back into the unified
/// [StreamEvent] types used throughout the codebase.
class GeminiClient extends ApiProvider {
  @override
  final ApiConfig config;

  static Logger get _log => SintSentinel.logger;

  /// Creates a client with the given Gemini [config].
  ///
  /// Requires [config.apiKey] to be non-null.
  GeminiClient(this.config) : assert(config.apiKey != null);

  // ── Message conversion: internal model → Gemini format ──

  /// Convert a [Message] to a Gemini `contents` entry.
  ///
  /// Gemini uses `"user"` and `"model"` roles (not `"assistant"`), and wraps
  /// each piece of content in a `parts` array containing `{"text": "..."}` or
  /// `{"inlineData": {...}}` objects.
  Map<String, dynamic> _convertMessage(Message msg) {
    final role = msg.role == MessageRole.assistant ? 'model' : 'user';
    final parts = <Map<String, dynamic>>[];

    for (final block in msg.content) {
      switch (block) {
        case TextBlock(text: final t):
          if (t.isNotEmpty) {
            parts.add({'text': t});
          }
        case ImageBlock(mediaType: final m, base64Data: final d):
          parts.add({
            'inlineData': {
              'mimeType': m,
              'data': d,
            },
          });
        case ToolResultBlock(toolUseId: final tid, content: final c):
          // Gemini expects function responses as parts.
          parts.add({
            'functionResponse': {
              'name': tid,
              'response': {'result': c},
            },
          });
        case ToolUseBlock(name: final n, input: final i, id: _):
          parts.add({
            'functionCall': {
              'name': n,
              'args': i,
            },
          });
      }
    }

    // Ensure at least one part — Gemini rejects empty parts arrays.
    if (parts.isEmpty) {
      parts.add({'text': ''});
    }

    return {'role': role, 'parts': parts};
  }

  /// Build the full request body for a Gemini API call.
  Map<String, dynamic> _buildRequestBody({
    required List<Message> messages,
    required String systemPrompt,
    required List<ToolDefinition> tools,
    int? maxTokens,
  }) {
    final contents = messages.map(_convertMessage).toList();

    final body = <String, dynamic>{
      'contents': contents,
      if (systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
      'generationConfig': {
        'maxOutputTokens': maxTokens ?? config.maxTokens,
      },
    };

    if (tools.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': tools.map((t) => t.toApiMap()).toList(),
        },
      ];
    }

    return body;
  }

  // ── Streaming ──

  /// Stream a message completion via the Gemini `streamGenerateContent` endpoint.
  ///
  /// The endpoint returns SSE events of the form:
  /// ```
  /// data: {"candidates":[{"content":{"parts":[{"text":"..."}]}}]}
  /// ```
  ///
  /// These are translated into the app's [StreamEvent] types so the rest of
  /// the codebase can consume them identically to Anthropic or OpenAI streams.
  Uri _resolveGeminiEndpoint(String action, {bool sse = false}) {
    final base = config.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final baseUri = Uri.tryParse(base);
    if (!NeomageNetworkGuard.isSafeEndpointUri(
      baseUri,
      allowLoopbackInsecure: false,
      secureSchemes: const <String>{'https'},
      insecureSchemes: const <String>{},
    )) {
      throw ArgumentError('Blocked unsafe Gemini baseUrl: $base');
    }
    final model = config.model.trim();
    if (!_safeModelNameRegex.hasMatch(model)) {
      throw ArgumentError('Blocked unsafe Gemini model identifier');
    }
    final raw = '$base/models/$model:$action${sse ? '?alt=sse' : ''}';
    final uri = Uri.tryParse(raw);
    if (!NeomageNetworkGuard.isSafeEndpointUri(
      uri,
      allowLoopbackInsecure: false,
      secureSchemes: const <String>{'https'},
      insecureSchemes: const <String>{},
    )) {
      throw ArgumentError('Blocked unsafe Gemini endpoint URI');
    }
    return uri!;
  }

  Map<String, String> _buildSafeHeaders() {
    final cleanKey = NeomageNetworkGuard.sanitizeHeaderValue(
      config.apiKey ?? '',
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (cleanKey.isNotEmpty) 'x-goog-api-key': cleanKey,
    };
    for (final entry in config.extraHeaders.entries) {
      final k = entry.key.trim();
      if (!NeomageNetworkGuard.isValidHeaderName(k)) continue;
      headers[k] = NeomageNetworkGuard.sanitizeHeaderValue(entry.value);
    }
    return headers;
  }

  @override
  Stream<StreamEvent> createMessageStream({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async* {
    final Uri uri;
    try {
      uri = _resolveGeminiEndpoint('streamGenerateContent', sse: true);
    } catch (e) {
      yield ErrorEvent(message: e.toString(), type: 'config_error');
      return;
    }

    final body = _buildRequestBody(
      messages: messages,
      systemPrompt: systemPrompt,
      tools: tools,
      maxTokens: maxTokens,
    );

    final request = http.Request('POST', uri)..followRedirects = false;
    request.headers.addAll(_buildSafeHeaders());
    request.body = jsonEncode(body);

    _log.d(
      'Gemini stream request to ${config.model} '
      '(key=${NeomageNetworkGuard.maskApiKey(config.apiKey)})',
    );

    final client = http.Client();
    try {
      http.StreamedResponse response;
      try {
        response = await SintSentinel.guard(
          () => client.send(request).timeout(_requestTimeout),
          tag: 'GeminiClient.createMessageStream',
        );
      } catch (e) {
        final safeErr = NeomageNetworkGuard.redactTransportError(e.toString());
        _log.e('Gemini connection error: $safeErr');
        yield ErrorEvent(
          message: 'Gemini connection error: $safeErr',
          type: 'network_error',
        );
        return;
      }

      if (response.statusCode != 200) {
        final rawErr = await _readBoundedUtf8(
          response.stream,
          _maxErrorBodyBytes,
        );
        final safeErr = NeomageNetworkGuard.sanitizeApiErrorBody(rawErr);
        _log.e('Gemini API error ${response.statusCode}: $safeErr');
        yield ErrorEvent(
          message: 'Gemini API error ${response.statusCode}: $safeErr',
          type: 'api_error',
        );
        return;
      }

      // Emit synthetic message-start event.
      final messageId = 'msg_${_uuid.v4()}';
      yield MessageStartEvent(messageId: messageId, model: config.model);

      var blockIndex = 0;
      var hasStartedText = false;

      await for (final event in _parseGeminiSSE(response.stream)) {
        final candidates = event['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          // Check for top-level errors.
          final error = event['error'];
          if (error is Map<String, dynamic>) {
            final safeMsg = NeomageNetworkGuard.redactTransportError(
              error['message']?.toString() ?? 'Unknown Gemini error',
            );
            yield ErrorEvent(message: safeMsg, type: 'api_error');
          }
          continue;
        }

        final firstCandidate = candidates[0];
        if (firstCandidate is! Map<String, dynamic>) continue;
        final content = firstCandidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;

        if (parts != null) {
          for (final part in parts) {
            if (part is! Map<String, dynamic>) continue;

            // Handle text content.
            final text = part['text'] as String?;
            if (text != null && text.isNotEmpty) {
              if (!hasStartedText) {
                yield ContentBlockStartEvent(
                  index: blockIndex,
                  block: const TextBlock(''),
                );
                hasStartedText = true;
              }
              yield ContentBlockDeltaEvent(index: blockIndex, text: text);
            }

            // Handle function calls (tool use).
            final functionCall = part['functionCall'];
            if (functionCall is Map<String, dynamic>) {
              if (hasStartedText) {
                yield ContentBlockStopEvent(index: blockIndex);
                blockIndex++;
                hasStartedText = false;
              }

              final name = functionCall['name'] as String? ?? '';
              final rawArgs = functionCall['args'];
              final args = rawArgs is Map<String, dynamic>
                  ? rawArgs
                  : <String, dynamic>{};
              final toolId = 'call_${_uuid.v4()}';

              yield ContentBlockStartEvent(
                index: blockIndex,
                block: ToolUseBlock(id: toolId, name: name, input: args),
              );
              // Emit the full arguments as a delta for consistency.
              yield ContentBlockDeltaEvent(
                index: blockIndex,
                text: jsonEncode(args),
              );
              yield ContentBlockStopEvent(index: blockIndex);
              blockIndex++;
            }
          }
        }

        // Check for finish reason.
        final finishReason = firstCandidate['finishReason'] as String?;
        if (finishReason != null) {
          if (hasStartedText) {
            yield ContentBlockStopEvent(index: blockIndex);
            hasStartedText = false;
          }

          final stopReason = _parseFinishReason(finishReason);
          final usageMetadata = event['usageMetadata'] as Map<String, dynamic>?;

          yield MessageDeltaEvent(
            stopReason: stopReason,
            usage: usageMetadata != null
                ? TokenUsage(
                    inputTokens:
                        usageMetadata['promptTokenCount'] as int? ?? 0,
                    outputTokens:
                        usageMetadata['candidatesTokenCount'] as int? ?? 0,
                  )
                : null,
          );
          yield const MessageStopEvent();
        }
      }
    } finally {
      client.close();
    }
  }

  // ── Non-streaming ──

  /// Send a non-streaming completion via the Gemini `generateContent` endpoint.
  @override
  Future<Message> createMessage({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  }) async {
    final uri = _resolveGeminiEndpoint('generateContent');
    final body = _buildRequestBody(
      messages: messages,
      systemPrompt: systemPrompt,
      tools: tools,
      maxTokens: maxTokens,
    );

    _log.d(
      'Gemini non-streaming request to ${config.model} '
      '(key=${NeomageNetworkGuard.maskApiKey(config.apiKey)})',
    );

    final client = http.Client();
    try {
      final request = http.Request('POST', uri)..followRedirects = false;
      request.headers.addAll(_buildSafeHeaders());
      request.body = jsonEncode(body);

      final streamed = await SintSentinel.guard(
        () => client.send(request).timeout(_requestTimeout),
        tag: 'GeminiClient.createMessage',
      );
      if (streamed.statusCode != 200) {
        final rawErr = await _readBoundedUtf8(
          streamed.stream,
          _maxErrorBodyBytes,
        );
        final safeErr = NeomageNetworkGuard.sanitizeApiErrorBody(rawErr);
        _log.e('Gemini API error ${streamed.statusCode}: $safeErr');
        throw Exception('Gemini API error ${streamed.statusCode}: $safeErr');
      }

      final respText = await _readBoundedUtf8(
        streamed.stream,
        _maxResponseBytes,
      );
      final decoded = jsonDecode(respText);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected non-object Gemini response');
      }
      return _parseResponse(decoded);
    } finally {
      client.close();
    }
  }

  // ── Response parsing ──

  /// Parse a non-streaming Gemini response into a [Message].
  Message _parseResponse(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return Message(
        role: MessageRole.assistant,
        content: [const TextBlock('No response from Gemini.')],
        stopReason: StopReason.endTurn,
      );
    }

    final firstCandidate = candidates[0];
    if (firstCandidate is! Map<String, dynamic>) {
      return Message(
        role: MessageRole.assistant,
        content: [const TextBlock('No response from Gemini.')],
        stopReason: StopReason.endTurn,
      );
    }
    final content = firstCandidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List? ?? [];
    final blocks = <ContentBlock>[];

    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;
      final text = part['text'] as String?;
      if (text != null) {
        blocks.add(TextBlock(text));
      }

      final functionCall = part['functionCall'];
      if (functionCall is Map<String, dynamic>) {
        final rawArgs = functionCall['args'];
        blocks.add(
          ToolUseBlock(
            id: 'call_${_uuid.v4()}',
            name: functionCall['name'] as String? ?? '',
            input: rawArgs is Map<String, dynamic> ? rawArgs : const {},
          ),
        );
      }
    }

    if (blocks.isEmpty) {
      blocks.add(const TextBlock(''));
    }

    final finishReason = firstCandidate['finishReason'] as String?;
    final usageMetadata = json['usageMetadata'] as Map<String, dynamic>?;

    return Message(
      role: MessageRole.assistant,
      content: blocks,
      stopReason: _parseFinishReason(finishReason),
      usage: usageMetadata != null
          ? TokenUsage(
              inputTokens: usageMetadata['promptTokenCount'] as int? ?? 0,
              outputTokens: usageMetadata['candidatesTokenCount'] as int? ?? 0,
            )
          : null,
    );
  }

  // ── SSE parsing ──

  /// Parse Gemini's SSE stream into decoded JSON objects.
  ///
  /// Gemini's streaming format sends `data: {json}` lines separated by blank
  /// lines, similar to standard SSE but without named event types.
  Stream<Map<String, dynamic>> _parseGeminiSSE(
    http.ByteStream byteStream,
  ) async* {
    await for (final line in byteStream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())) {
      if (line.length > _maxSseLineChars) {
        _log.w('Dropped oversized Gemini SSE line (> $_maxSseLineChars chars)');
        continue;
      }
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map<String, dynamic>) {
            yield decoded;
          }
        } catch (e) {
          _log.w('Failed to parse Gemini SSE data');
        }
      }
    }
  }

  // ── Helpers ──

  /// Map Gemini finish reasons to the app's [StopReason] enum.
  StopReason? _parseFinishReason(String? reason) => switch (reason) {
        'STOP' => StopReason.endTurn,
        'MAX_TOKENS' => StopReason.maxTokens,
        'SAFETY' => StopReason.endTurn,
        'RECITATION' => StopReason.endTurn,
        'OTHER' => StopReason.endTurn,
        _ => null,
      };
}
