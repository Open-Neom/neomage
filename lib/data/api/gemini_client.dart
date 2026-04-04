import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sint_sentinel/sint_sentinel.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';
import 'api_provider.dart';

const _uuid = Uuid();

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
    );

    final url = '${config.baseUrl}/models/${config.model}'
        ':streamGenerateContent?alt=sse&key=${config.apiKey}';

    final request = http.Request('POST', Uri.parse(url));
    request.headers.addAll({
      'Content-Type': 'application/json',
      ...config.extraHeaders,
    });
    request.body = jsonEncode(body);

    _log.d('Gemini stream request to ${config.model}');

    final client = http.Client();
    http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (e) {
      client.close();
      _log.e('Gemini connection error', error: e);
      yield ErrorEvent(message: 'Gemini connection error: $e', type: 'network_error');
      return;
    }

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      client.close();
      _log.e('Gemini API error ${response.statusCode}: $errorBody');
      yield ErrorEvent(
        message: 'Gemini API error ${response.statusCode}: $errorBody',
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
        final error = event['error'] as Map<String, dynamic>?;
        if (error != null) {
          yield ErrorEvent(
            message: error['message'] as String? ?? 'Unknown Gemini error',
            type: 'api_error',
          );
        }
        continue;
      }

      final candidate = candidates[0] as Map<String, dynamic>;
      final content = candidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;

      if (parts != null) {
        for (final part in parts) {
          final partMap = part as Map<String, dynamic>;

          // Handle text content.
          final text = partMap['text'] as String?;
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
          final functionCall = partMap['functionCall'] as Map<String, dynamic>?;
          if (functionCall != null) {
            if (hasStartedText) {
              yield ContentBlockStopEvent(index: blockIndex);
              blockIndex++;
              hasStartedText = false;
            }

            final name = functionCall['name'] as String? ?? '';
            final args =
                (functionCall['args'] as Map<String, dynamic>?) ?? {};
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
      final finishReason = candidate['finishReason'] as String?;
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

    client.close();
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
    final body = _buildRequestBody(
      messages: messages,
      systemPrompt: systemPrompt,
      tools: tools,
      maxTokens: maxTokens,
    );

    final url = '${config.baseUrl}/models/${config.model}'
        ':generateContent?key=${config.apiKey}';

    _log.d('Gemini non-streaming request to ${config.model}');

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        ...config.extraHeaders,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      _log.e('Gemini API error ${response.statusCode}: ${response.body}');
      throw Exception(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    return _parseResponse(jsonDecode(response.body) as Map<String, dynamic>);
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

    final candidate = candidates[0] as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List? ?? [];
    final blocks = <ContentBlock>[];

    for (final part in parts) {
      final partMap = part as Map<String, dynamic>;
      final text = partMap['text'] as String?;
      if (text != null) {
        blocks.add(TextBlock(text));
      }

      final functionCall = partMap['functionCall'] as Map<String, dynamic>?;
      if (functionCall != null) {
        blocks.add(ToolUseBlock(
          id: 'call_${_uuid.v4()}',
          name: functionCall['name'] as String? ?? '',
          input: (functionCall['args'] as Map<String, dynamic>?) ?? {},
        ));
      }
    }

    if (blocks.isEmpty) {
      blocks.add(const TextBlock(''));
    }

    final finishReason = candidate['finishReason'] as String?;
    final usageMetadata = json['usageMetadata'] as Map<String, dynamic>?;

    return Message(
      role: MessageRole.assistant,
      content: blocks,
      stopReason: _parseFinishReason(finishReason),
      usage: usageMetadata != null
          ? TokenUsage(
              inputTokens: usageMetadata['promptTokenCount'] as int? ?? 0,
              outputTokens:
                  usageMetadata['candidatesTokenCount'] as int? ?? 0,
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
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        try {
          yield jsonDecode(data) as Map<String, dynamic>;
        } catch (e) {
          _log.w('Failed to parse Gemini SSE data', error: e);
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
