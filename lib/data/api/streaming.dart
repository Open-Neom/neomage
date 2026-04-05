// API streaming — port of neomage/src/services/api/ streaming infrastructure.
// SSE parsing, streaming message assembly, multimodal content handling.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../domain/models/message.dart';
import 'api_provider.dart';
import 'errors.dart';

// ---------------------------------------------------------------------------
// SSE Parser
// ---------------------------------------------------------------------------

/// A single parsed SSE field set (one event).
class SseEvent {
  final String? eventType;
  final String data;
  final String? id;
  final int? retry;

  const SseEvent({this.eventType, required this.data, this.id, this.retry});
}

/// Server-Sent Events parser for Anthropic streaming API.
///
/// Conforms to the W3C EventSource spec:
///  - Lines starting with "event:" set the event type.
///  - Lines starting with "data:" append to the data buffer.
///  - Lines starting with "id:" set the last-event-id.
///  - Lines starting with "retry:" suggest a reconnection interval.
///  - An empty line dispatches the accumulated event.
///  - Lines starting with ":" are comments and are ignored.
class SseParser {
  String _eventType = '';
  final StringBuffer _dataBuffer = StringBuffer();
  String _lastId = '';
  int? _retry;
  String _lineCarry = '';

  /// Transform a raw byte stream into a stream of [SseEvent]s.
  Stream<SseEvent> parse(Stream<List<int>> byteStream) async* {
    final lineStream = byteStream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final rawLine in lineStream) {
      // Handle partial lines carried from previous chunk.
      final line = _lineCarry.isEmpty ? rawLine : '$_lineCarry$rawLine';
      _lineCarry = '';

      // Comment line — ignore.
      if (line.startsWith(':')) continue;

      // Empty line — dispatch accumulated event.
      if (line.isEmpty) {
        if (_dataBuffer.isNotEmpty) {
          final data = _dataBuffer.toString();
          // Remove trailing newline if present.
          final trimmed = data.endsWith('\n')
              ? data.substring(0, data.length - 1)
              : data;
          yield SseEvent(
            eventType: _eventType.isNotEmpty ? _eventType : null,
            data: trimmed,
            id: _lastId.isNotEmpty ? _lastId : null,
            retry: _retry,
          );
        }
        // Reset per-event state.
        _eventType = '';
        _dataBuffer.clear();
        _retry = null;
        continue;
      }

      // Parse field.
      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) {
        // Field name with no value — treat value as empty string.
        _processField(line, '');
      } else {
        final fieldName = line.substring(0, colonIdx);
        var value = line.substring(colonIdx + 1);
        // Strip single leading space from value per spec.
        if (value.startsWith(' ')) value = value.substring(1);
        _processField(fieldName, value);
      }
    }
  }

  void _processField(String field, String value) {
    switch (field) {
      case 'event':
        _eventType = value;
      case 'data':
        _dataBuffer.write(value);
        _dataBuffer.write('\n');
      case 'id':
        if (!value.contains('\u0000')) _lastId = value;
      case 'retry':
        final ms = int.tryParse(value);
        if (ms != null) _retry = ms;
      // Unknown fields are ignored per spec.
    }
  }

  /// Reset parser state (useful between reconnections).
  void reset() {
    _eventType = '';
    _dataBuffer.clear();
    _lastId = '';
    _retry = null;
    _lineCarry = '';
  }
}

// ---------------------------------------------------------------------------
// Stream event types
// ---------------------------------------------------------------------------

/// SSE event types from Anthropic API.
enum StreamEventType {
  messageStart,
  contentBlockStart,
  contentBlockDelta,
  contentBlockStop,
  messageDelta,
  messageStop,
  ping,
  error,
}

/// Map raw SSE event type strings to [StreamEventType].
StreamEventType? parseStreamEventType(String raw) => switch (raw) {
  'message_start' => StreamEventType.messageStart,
  'content_block_start' => StreamEventType.contentBlockStart,
  'content_block_delta' => StreamEventType.contentBlockDelta,
  'content_block_stop' => StreamEventType.contentBlockStop,
  'message_delta' => StreamEventType.messageDelta,
  'message_stop' => StreamEventType.messageStop,
  'ping' => StreamEventType.ping,
  'error' => StreamEventType.error,
  _ => null,
};

// ---------------------------------------------------------------------------
// Stream update events emitted to UI
// ---------------------------------------------------------------------------

/// Stream update events emitted to UI.
sealed class StreamUpdate {
  const StreamUpdate();
}

/// A text delta for an assistant text block.
class TextDelta extends StreamUpdate {
  final String text;
  final int blockIndex;
  const TextDelta({required this.text, required this.blockIndex});

  @override
  String toString() =>
      'TextDelta(block=$blockIndex, "${text.length > 40 ? '${text.substring(0, 40)}...' : text}")';
}

/// A thinking/reasoning delta.
class ThinkingDelta extends StreamUpdate {
  final String text;
  final int blockIndex;
  const ThinkingDelta({required this.text, required this.blockIndex});

  @override
  String toString() => 'ThinkingDelta(block=$blockIndex, len=${text.length})';
}

/// Signals the start of a tool_use block.
class ToolUseStart extends StreamUpdate {
  final String toolName;
  final String toolId;
  final int blockIndex;
  const ToolUseStart({
    required this.toolName,
    required this.toolId,
    required this.blockIndex,
  });

  @override
  String toString() => 'ToolUseStart($toolName, id=$toolId)';
}

/// Partial JSON input delta for a tool_use block.
class ToolUseInputDelta extends StreamUpdate {
  final String partialJson;
  final int blockIndex;
  const ToolUseInputDelta({
    required this.partialJson,
    required this.blockIndex,
  });
}

/// Signals that a tool_use block is complete with fully parsed input.
class ToolUseComplete extends StreamUpdate {
  final String toolName;
  final String toolId;
  final Map<String, dynamic> input;
  final int blockIndex;
  const ToolUseComplete({
    required this.toolName,
    required this.toolId,
    required this.input,
    required this.blockIndex,
  });

  @override
  String toString() => 'ToolUseComplete($toolName, keys=${input.keys})';
}

/// Token usage update.
class UsageUpdate extends StreamUpdate {
  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;
  const UsageUpdate({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });

  int get totalTokens => inputTokens + outputTokens;

  @override
  String toString() => 'UsageUpdate(in=$inputTokens, out=$outputTokens)';
}

/// The message is complete.
class MessageComplete extends StreamUpdate {
  final String? stopReason;
  final String? messageId;
  final String? model;
  const MessageComplete({this.stopReason, this.messageId, this.model});

  @override
  String toString() => 'MessageComplete(stop=$stopReason)';
}

/// A stream-level error.
class StreamError extends StreamUpdate {
  final String message;
  final String? errorType;
  const StreamError({required this.message, this.errorType});

  @override
  String toString() => 'StreamError($errorType: $message)';
}

/// Message started — carries model and message id metadata.
class MessageStartUpdate extends StreamUpdate {
  final String messageId;
  final String model;
  final TokenUsage? usage;
  const MessageStartUpdate({
    required this.messageId,
    required this.model,
    this.usage,
  });
}

// ---------------------------------------------------------------------------
// Content block accumulators
// ---------------------------------------------------------------------------

/// Content block accumulator — assembles deltas into a complete block.
sealed class ContentBlockAccumulator {
  final int index;
  const ContentBlockAccumulator(this.index);

  /// Build the final [ContentBlock].
  ContentBlock toContentBlock();
}

/// Accumulates text deltas into a complete [TextBlock].
class TextAccumulator extends ContentBlockAccumulator {
  final StringBuffer _buffer = StringBuffer();

  TextAccumulator(super.index, [String initial = '']) {
    if (initial.isNotEmpty) _buffer.write(initial);
  }

  void append(String text) => _buffer.write(text);
  String get currentText => _buffer.toString();

  @override
  ContentBlock toContentBlock() => TextBlock(currentText);
}

/// Accumulates thinking/reasoning text.
class ThinkingAccumulator extends ContentBlockAccumulator {
  final StringBuffer _buffer = StringBuffer();

  ThinkingAccumulator(super.index, [String initial = '']) {
    if (initial.isNotEmpty) _buffer.write(initial);
  }

  void append(String text) => _buffer.write(text);
  String get currentText => _buffer.toString();

  @override
  ContentBlock toContentBlock() => TextBlock(currentText);
}

/// Accumulates tool_use JSON input from partial_json deltas.
class ToolUseAccumulator extends ContentBlockAccumulator {
  final String toolId;
  final String toolName;
  final StringBuffer _jsonBuffer = StringBuffer();

  ToolUseAccumulator(
    super.index, {
    required this.toolId,
    required this.toolName,
  });

  void append(String partialJson) => _jsonBuffer.write(partialJson);

  String get currentJson => _jsonBuffer.toString();

  Map<String, dynamic> get parsedInput {
    final raw = currentJson;
    if (raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  ContentBlock toContentBlock() =>
      ToolUseBlock(id: toolId, name: toolName, input: parsedInput);
}

/// Holds image data received in a content block.
class ImageAccumulator extends ContentBlockAccumulator {
  final String mediaType;
  final String base64Data;

  ImageAccumulator(
    super.index, {
    required this.mediaType,
    required this.base64Data,
  });

  @override
  ContentBlock toContentBlock() =>
      ImageBlock(mediaType: mediaType, base64Data: base64Data);
}

// ---------------------------------------------------------------------------
// Streaming state
// ---------------------------------------------------------------------------

/// Streaming state for a single API call — tracks all content blocks and
/// emits [StreamUpdate]s as deltas arrive.
class StreamingState {
  String? messageId;
  String? model;
  final List<ContentBlockAccumulator> contentBlocks = [];
  final StreamController<StreamUpdate> _controller =
      StreamController<StreamUpdate>.broadcast();

  int _inputTokens = 0;
  int _outputTokens = 0;
  int? _cacheCreationTokens;
  int? _cacheReadTokens;
  String? stopReason;

  /// The update stream that UI listens to.
  Stream<StreamUpdate> get updates => _controller.stream;

  bool get isComplete => stopReason != null;

  TokenUsage get usage => TokenUsage(
    inputTokens: _inputTokens,
    outputTokens: _outputTokens,
    cacheCreationInputTokens: _cacheCreationTokens,
    cacheReadInputTokens: _cacheReadTokens,
  );

  /// Build the final assembled [Message].
  Message toMessage() => Message(
    id: messageId,
    role: MessageRole.assistant,
    content: contentBlocks.map((b) => b.toContentBlock()).toList(),
    stopReason: _mapStopReason(stopReason),
    usage: usage,
  );

  void _emit(StreamUpdate update) {
    if (!_controller.isClosed) _controller.add(update);
  }

  void close() {
    if (!_controller.isClosed) _controller.close();
  }

  StopReason? _mapStopReason(String? reason) => switch (reason) {
    'end_turn' => StopReason.endTurn,
    'max_tokens' => StopReason.maxTokens,
    'tool_use' => StopReason.toolUse,
    'stop_sequence' => StopReason.stopSequence,
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// Stream assembler
// ---------------------------------------------------------------------------

/// Stream assembler — processes raw SSE events into [StreamUpdate]s and
/// maintains a [StreamingState] that accumulates the full message.
class StreamAssembler {
  final StreamingState state = StreamingState();

  /// Process a raw SSE event type and JSON data payload.
  void processEvent(String eventType, Map<String, dynamic> data) {
    final type = parseStreamEventType(eventType);
    if (type == null) return;

    switch (type) {
      case StreamEventType.messageStart:
        _handleMessageStart(data);
      case StreamEventType.contentBlockStart:
        _handleContentBlockStart(data);
      case StreamEventType.contentBlockDelta:
        _handleContentBlockDelta(data);
      case StreamEventType.contentBlockStop:
        _handleContentBlockStop(data);
      case StreamEventType.messageDelta:
        _handleMessageDelta(data);
      case StreamEventType.messageStop:
        _handleMessageStop();
      case StreamEventType.ping:
        break; // Heartbeat — no action needed.
      case StreamEventType.error:
        _handleError(data);
    }
  }

  void _handleMessageStart(Map<String, dynamic> data) {
    final message = data['message'] as Map<String, dynamic>? ?? {};
    state.messageId = message['id'] as String?;
    state.model = message['model'] as String?;

    final usageData = message['usage'] as Map<String, dynamic>?;
    TokenUsage? startUsage;
    if (usageData != null) {
      state._inputTokens = usageData['input_tokens'] as int? ?? 0;
      state._outputTokens = usageData['output_tokens'] as int? ?? 0;
      state._cacheCreationTokens =
          usageData['cache_creation_input_tokens'] as int?;
      state._cacheReadTokens = usageData['cache_read_input_tokens'] as int?;
      startUsage = TokenUsage.fromJson(usageData);
    }

    state._emit(
      MessageStartUpdate(
        messageId: state.messageId ?? '',
        model: state.model ?? '',
        usage: startUsage,
      ),
    );
  }

  void _handleContentBlockStart(Map<String, dynamic> data) {
    final index = data['index'] as int;
    final block = data['content_block'] as Map<String, dynamic>? ?? {};
    final blockType = block['type'] as String? ?? 'text';

    switch (blockType) {
      case 'text':
        final initial = block['text'] as String? ?? '';
        state.contentBlocks.add(TextAccumulator(index, initial));
        if (initial.isNotEmpty) {
          state._emit(TextDelta(text: initial, blockIndex: index));
        }
      case 'thinking':
        final initial = block['thinking'] as String? ?? '';
        state.contentBlocks.add(ThinkingAccumulator(index, initial));
        if (initial.isNotEmpty) {
          state._emit(ThinkingDelta(text: initial, blockIndex: index));
        }
      case 'tool_use':
        final toolId = block['id'] as String? ?? '';
        final toolName = block['name'] as String? ?? '';
        state.contentBlocks.add(
          ToolUseAccumulator(index, toolId: toolId, toolName: toolName),
        );
        state._emit(
          ToolUseStart(toolName: toolName, toolId: toolId, blockIndex: index),
        );
      case 'image':
        final source = block['source'] as Map<String, dynamic>? ?? {};
        state.contentBlocks.add(
          ImageAccumulator(
            index,
            mediaType: source['media_type'] as String? ?? 'image/png',
            base64Data: source['data'] as String? ?? '',
          ),
        );
      default:
        // Unknown block type — treat as text.
        state.contentBlocks.add(TextAccumulator(index));
    }
  }

  void _handleContentBlockDelta(Map<String, dynamic> data) {
    final index = data['index'] as int;
    final delta = data['delta'] as Map<String, dynamic>? ?? {};
    final deltaType = delta['type'] as String? ?? '';

    final accumulator = _findAccumulator(index);
    if (accumulator == null) return;

    switch (deltaType) {
      case 'text_delta':
        final text = delta['text'] as String? ?? '';
        if (accumulator is TextAccumulator) {
          accumulator.append(text);
          state._emit(TextDelta(text: text, blockIndex: index));
        }
      case 'thinking_delta':
        final text = delta['thinking'] as String? ?? '';
        if (accumulator is ThinkingAccumulator) {
          accumulator.append(text);
          state._emit(ThinkingDelta(text: text, blockIndex: index));
        }
      case 'input_json_delta':
        final partialJson = delta['partial_json'] as String? ?? '';
        if (accumulator is ToolUseAccumulator) {
          accumulator.append(partialJson);
          state._emit(
            ToolUseInputDelta(partialJson: partialJson, blockIndex: index),
          );
        }
    }
  }

  void _handleContentBlockStop(Map<String, dynamic> data) {
    final index = data['index'] as int;
    final accumulator = _findAccumulator(index);
    if (accumulator == null) return;

    // Emit completion event for tool_use blocks.
    if (accumulator is ToolUseAccumulator) {
      state._emit(
        ToolUseComplete(
          toolName: accumulator.toolName,
          toolId: accumulator.toolId,
          input: accumulator.parsedInput,
          blockIndex: index,
        ),
      );
    }
  }

  void _handleMessageDelta(Map<String, dynamic> data) {
    final delta = data['delta'] as Map<String, dynamic>? ?? {};
    final usageData = data['usage'] as Map<String, dynamic>?;

    state.stopReason = delta['stop_reason'] as String?;

    if (usageData != null) {
      state._outputTokens =
          usageData['output_tokens'] as int? ?? state._outputTokens;
      state._emit(
        UsageUpdate(
          inputTokens: state._inputTokens,
          outputTokens: state._outputTokens,
          cacheCreationInputTokens: state._cacheCreationTokens,
          cacheReadInputTokens: state._cacheReadTokens,
        ),
      );
    }
  }

  void _handleMessageStop() {
    state._emit(
      MessageComplete(
        stopReason: state.stopReason,
        messageId: state.messageId,
        model: state.model,
      ),
    );
    state.close();
  }

  void _handleError(Map<String, dynamic> data) {
    final error = data['error'] as Map<String, dynamic>? ?? data;
    state._emit(
      StreamError(
        message: error['message'] as String? ?? 'Unknown stream error',
        errorType: error['type'] as String?,
      ),
    );
  }

  ContentBlockAccumulator? _findAccumulator(int index) {
    for (final acc in state.contentBlocks) {
      if (acc.index == index) return acc;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Top-level stream processing
// ---------------------------------------------------------------------------

/// Process an HTTP streaming response byte stream into [StreamUpdate]s.
///
/// This is the primary entry point for consuming a streaming API response.
/// It performs full SSE parsing, event assembly, and emits high-level updates
/// suitable for driving UI.
///
/// The returned [StreamAssembler] can be used after the stream completes to
/// retrieve the fully assembled [Message] via `assembler.state.toMessage()`.
(Stream<StreamUpdate>, StreamAssembler) processStreamWithAssembler(
  Stream<List<int>> byteStream,
) {
  final parser = SseParser();
  final assembler = StreamAssembler();

  final stream = _processStreamImpl(byteStream, parser, assembler);
  return (stream, assembler);
}

Stream<StreamUpdate> _processStreamImpl(
  Stream<List<int>> byteStream,
  SseParser parser,
  StreamAssembler assembler,
) async* {
  await for (final sseEvent in parser.parse(byteStream)) {
    final eventType = sseEvent.eventType;
    if (eventType == null) continue;

    // Skip ping events at SSE level.
    if (eventType == 'ping') continue;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(sseEvent.data) as Map<String, dynamic>;
    } catch (e) {
      yield StreamError(
        message: 'Failed to parse SSE data: $e',
        errorType: 'parse_error',
      );
      continue;
    }

    assembler.processEvent(eventType, data);
  }

  // If stream ended without a message_stop, emit completion anyway.
  if (!assembler.state.isComplete) {
    yield MessageComplete(
      stopReason: assembler.state.stopReason,
      messageId: assembler.state.messageId,
      model: assembler.state.model,
    );
    assembler.state.close();
  }
}

/// Convenience: process a byte stream and yield [StreamUpdate]s directly.
Stream<StreamUpdate> processStream(Stream<List<int>> byteStream) async* {
  final (stream, _) = processStreamWithAssembler(byteStream);
  yield* stream;
}

// ---------------------------------------------------------------------------
// Multimodal content helpers
// ---------------------------------------------------------------------------

/// Encode raw image bytes for Anthropic API submission.
///
/// Returns a content block map with base64-encoded image data.
/// Supported media types: image/jpeg, image/png, image/gif, image/webp.
Map<String, dynamic> encodeImageContent(List<int> bytes, String mediaType) {
  final base64Data = base64Encode(bytes);
  return {
    'type': 'image',
    'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Data},
  };
}

/// Encode raw PDF bytes for Anthropic API submission.
///
/// Returns a content block map with base64-encoded document data.
Map<String, dynamic> encodePdfContent(List<int> bytes) {
  final base64Data = base64Encode(bytes);
  return {
    'type': 'document',
    'source': {
      'type': 'base64',
      'media_type': 'application/pdf',
      'data': base64Data,
    },
  };
}

/// Detect image media type from file extension.
String? mediaTypeFromExtension(String extension) =>
    switch (extension.toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => null,
    };

/// Detect image media type from magic bytes.
String? mediaTypeFromBytes(List<int> bytes) {
  if (bytes.length < 4) return null;
  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  // PNG: 89 50 4E 47
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  // GIF: 47 49 46 38
  if (bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return 'image/gif';
  }
  // WebP: 52 49 46 46 ... 57 45 42 50
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  // PDF: 25 50 44 46 (%PDF)
  if (bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return 'application/pdf';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Prompt caching
// ---------------------------------------------------------------------------

/// Configuration for Anthropic prompt caching.
class CacheConfig {
  /// Whether caching is enabled.
  final bool enabled;

  /// Indices of messages (in the messages array) whose last content block
  /// should receive a `cache_control` ephemeral marker. Typically the system
  /// prompt and the most recent few turns benefit most from caching.
  final List<int> breakpoints;

  /// Minimum number of tokens a cacheable prefix should have (API requires
  /// at least 1024 tokens for caching to be effective with Neomage models).
  final int minTokensForCache;

  const CacheConfig({
    this.enabled = true,
    this.breakpoints = const [],
    this.minTokensForCache = 1024,
  });

  static const CacheConfig disabled = CacheConfig(enabled: false);

  /// Auto breakpoints: cache the system prompt (index -1 signals system)
  /// and the last user message.
  factory CacheConfig.auto({int? messageCount}) => CacheConfig(
    enabled: true,
    breakpoints: messageCount != null && messageCount > 0
        ? [0, messageCount - 1]
        : const [0],
  );
}

/// Apply cache breakpoints to a list of message maps destined for the API.
///
/// Inserts `cache_control: {"type": "ephemeral"}` on the last content block
/// of each message at the specified breakpoint indices.
List<Map<String, dynamic>> applyCacheBreakpoints(
  List<Map<String, dynamic>> messages,
  CacheConfig config,
) {
  if (!config.enabled || config.breakpoints.isEmpty) return messages;

  // Deep copy to avoid mutating the originals.
  final result = messages.map((m) => Map<String, dynamic>.from(m)).toList();

  for (final idx in config.breakpoints) {
    if (idx < 0 || idx >= result.length) continue;

    final message = result[idx];
    final content = message['content'];
    if (content is List && content.isNotEmpty) {
      final contentList = List<Map<String, dynamic>>.from(
        content.map((c) => Map<String, dynamic>.from(c as Map)),
      );
      // Mark the last content block.
      contentList.last['cache_control'] = {'type': 'ephemeral'};
      message['content'] = contentList;
    } else if (content is String) {
      // If content is a plain string, wrap it in a block with cache_control.
      message['content'] = [
        {
          'type': 'text',
          'text': content,
          'cache_control': {'type': 'ephemeral'},
        },
      ];
    }
  }

  return result;
}

/// Apply cache control to a system prompt (list of system content blocks).
List<Map<String, dynamic>> applyCacheToSystem(
  List<Map<String, dynamic>> systemBlocks,
) {
  if (systemBlocks.isEmpty) return systemBlocks;

  final result = systemBlocks.map((b) => Map<String, dynamic>.from(b)).toList();
  result.last['cache_control'] = {'type': 'ephemeral'};
  return result;
}

// ---------------------------------------------------------------------------
// Rate limiter
// ---------------------------------------------------------------------------

/// Token-bucket rate limiter for API calls.
///
/// Tracks both requests-per-minute and tokens-per-minute to stay within
/// Anthropic rate limits. Uses a sliding window approach.
class RateLimiter {
  final int maxRequestsPerMinute;
  final int maxTokensPerMinute;

  final List<DateTime> _requestTimestamps = [];
  final List<_TokenRecord> _tokenRecords = [];
  int _consecutiveRateLimits = 0;

  RateLimiter({
    this.maxRequestsPerMinute = 50,
    this.maxTokensPerMinute = 100000,
  });

  /// Check whether a request with [estimatedTokens] can proceed.
  ///
  /// Returns [Duration.zero] if the request can proceed immediately, or a
  /// positive duration indicating how long to wait.
  Duration checkLimit({int estimatedTokens = 0}) {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(minutes: 1));

    // Prune old entries outside the sliding window.
    _requestTimestamps.removeWhere((t) => t.isBefore(windowStart));
    _tokenRecords.removeWhere((r) => r.timestamp.isBefore(windowStart));

    // Check request rate.
    if (_requestTimestamps.length >= maxRequestsPerMinute) {
      final oldest = _requestTimestamps.first;
      final waitUntil = oldest.add(const Duration(minutes: 1));
      final delay = waitUntil.difference(now);
      if (delay > Duration.zero) return delay;
    }

    // Check token rate.
    if (estimatedTokens > 0) {
      final tokensInWindow = _tokenRecords.fold<int>(
        0,
        (sum, r) => sum + r.tokens,
      );
      if (tokensInWindow + estimatedTokens > maxTokensPerMinute) {
        final oldest = _tokenRecords.first;
        final waitUntil = oldest.timestamp.add(const Duration(minutes: 1));
        final delay = waitUntil.difference(now);
        if (delay > Duration.zero) return delay;
      }
    }

    return Duration.zero;
  }

  /// Record that a request was made.
  void recordRequest({int tokens = 0}) {
    final now = DateTime.now();
    _requestTimestamps.add(now);
    if (tokens > 0) {
      _tokenRecords.add(_TokenRecord(now, tokens));
    }
    _consecutiveRateLimits = 0;
  }

  /// Record a rate limit (429) response. Returns the recommended backoff.
  Duration recordRateLimit() {
    _consecutiveRateLimits++;
    final backoffMs = (pow(2, _consecutiveRateLimits) * 1000).toInt().clamp(
      1000,
      60000,
    );
    final jitter = Random().nextInt(500);
    return Duration(milliseconds: backoffMs + jitter);
  }

  /// Reset rate limit tracking (e.g. after a long pause).
  void reset() {
    _requestTimestamps.clear();
    _tokenRecords.clear();
    _consecutiveRateLimits = 0;
  }
}

class _TokenRecord {
  final DateTime timestamp;
  final int tokens;
  const _TokenRecord(this.timestamp, this.tokens);
}

// ---------------------------------------------------------------------------
// Retry logic (streaming-aware wrapper)
// ---------------------------------------------------------------------------

/// Set of HTTP status codes that are retryable.
const _retryableStatusCodes = {429, 500, 502, 503, 529};

/// Set of HTTP status codes that should NOT be retried.
const _nonRetryableStatusCodes = {400, 401, 403, 404};

/// Determine if an HTTP status code is retryable.
bool isRetryableStatus(int statusCode) =>
    _retryableStatusCodes.contains(statusCode);

/// Determine if an HTTP status code should NOT be retried.
bool isNonRetryableStatus(int statusCode) =>
    _nonRetryableStatusCodes.contains(statusCode);

/// Execute an async operation with exponential backoff and jitter.
///
/// This is a streaming-aware retry wrapper that complements the existing
/// [withRetry] in `retry.dart`. It operates on raw futures rather than
/// [ApiError] types, making it suitable for use outside the [ApiProvider]
/// abstraction.
Future<T> withStreamRetry<T>(
  Future<T> Function() fn, {
  int maxRetries = 3,
  Duration initialDelay = const Duration(seconds: 1),
  Duration maxDelay = const Duration(seconds: 30),
  bool Function(Object error)? shouldRetry,
}) async {
  final random = Random();
  var attempt = 0;

  while (true) {
    try {
      return await fn();
    } catch (e) {
      attempt++;
      if (attempt >= maxRetries) rethrow;

      // Check custom retry predicate.
      if (shouldRetry != null && !shouldRetry(e)) rethrow;

      // Default: retry on ApiError if retryable, otherwise don't.
      if (shouldRetry == null) {
        if (e is ApiError && !e.isRetryable) rethrow;
      }

      // Calculate backoff with jitter.
      final baseMs = initialDelay.inMilliseconds * pow(2, attempt - 1);
      final jitter = random.nextDouble() * 0.25 * baseMs;
      final delayMs = (baseMs + jitter).toInt().clamp(
        initialDelay.inMilliseconds,
        maxDelay.inMilliseconds,
      );

      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
}

// ---------------------------------------------------------------------------
// Stream-to-message converter
// ---------------------------------------------------------------------------

/// Consume a [Stream<StreamUpdate>] and assemble the final [Message].
///
/// Optionally invokes [onUpdate] for each intermediate update (useful for
/// driving progress UI while still awaiting the complete message).
Future<Message> collectStreamToMessage(
  Stream<StreamUpdate> stream, {
  void Function(StreamUpdate update)? onUpdate,
}) async {
  String? accMessageId;
  // ignore: unused_local_variable
  String? accModel;
  String? stopReason;
  int inputTokens = 0;
  int outputTokens = 0;
  int? cacheCreationTokens;
  int? cacheReadTokens;
  final blocks = <int, ContentBlockAccumulator>{};

  await for (final update in stream) {
    onUpdate?.call(update);

    switch (update) {
      case MessageStartUpdate():
        accMessageId = update.messageId;
        accModel = update.model;
        if (update.usage != null) {
          inputTokens = update.usage!.inputTokens;
          outputTokens = update.usage!.outputTokens;
          cacheCreationTokens = update.usage!.cacheCreationInputTokens;
          cacheReadTokens = update.usage!.cacheReadInputTokens;
        }
      case TextDelta(:final text, :final blockIndex):
        final acc = blocks.putIfAbsent(
          blockIndex,
          () => TextAccumulator(blockIndex),
        );
        if (acc is TextAccumulator) acc.append(text);
      case ThinkingDelta(:final text, :final blockIndex):
        final acc = blocks.putIfAbsent(
          blockIndex,
          () => ThinkingAccumulator(blockIndex),
        );
        if (acc is ThinkingAccumulator) acc.append(text);
      case ToolUseStart(:final toolName, :final toolId, :final blockIndex):
        blocks.putIfAbsent(
          blockIndex,
          () => ToolUseAccumulator(
            blockIndex,
            toolId: toolId,
            toolName: toolName,
          ),
        );
      case ToolUseInputDelta(:final partialJson, :final blockIndex):
        final acc = blocks[blockIndex];
        if (acc is ToolUseAccumulator) acc.append(partialJson);
      case UsageUpdate():
        inputTokens = update.inputTokens;
        outputTokens = update.outputTokens;
        cacheCreationTokens = update.cacheCreationInputTokens;
        cacheReadTokens = update.cacheReadInputTokens;
      case MessageComplete():
        stopReason = update.stopReason;
      case StreamError(:final message):
        throw ApiError(type: ApiErrorType.unknown, message: message);
      default:
        break;
    }
  }

  // Sort blocks by index and build content.
  final sortedKeys = blocks.keys.toList()..sort();
  final content = sortedKeys.map((k) => blocks[k]!.toContentBlock()).toList();

  final stopReasonEnum = switch (stopReason) {
    'end_turn' => StopReason.endTurn,
    'max_tokens' => StopReason.maxTokens,
    'tool_use' => StopReason.toolUse,
    'stop_sequence' => StopReason.stopSequence,
    _ => null,
  };

  return Message(
    id: accMessageId,
    role: MessageRole.assistant,
    content: content.isEmpty ? [const TextBlock('')] : content,
    stopReason: stopReasonEnum,
    usage: TokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheCreationInputTokens: cacheCreationTokens,
      cacheReadInputTokens: cacheReadTokens,
    ),
  );
}

// ---------------------------------------------------------------------------
// Stream event conversion (bridge from api_provider.dart StreamEvent)
// ---------------------------------------------------------------------------

/// Convert the existing [StreamEvent] (from api_provider.dart) sequence
/// into the higher-level [StreamUpdate] sequence used by this module.
///
/// This enables interop: callers using [ApiProvider.createMessageStream]
/// can pipe its events through this converter to get [StreamUpdate]s.
Stream<StreamUpdate> convertProviderStream(
  Stream<StreamEvent> providerStream,
) async* {
  final assembler = StreamAssembler();

  await for (final event in providerStream) {
    switch (event) {
      case MessageStartEvent(:final messageId, :final model):
        assembler.processEvent('message_start', {
          'message': {'id': messageId, 'model': model},
        });
        yield MessageStartUpdate(messageId: messageId, model: model);

      case ContentBlockStartEvent(:final index, :final block):
        final blockMap = _contentBlockToMap(block);
        assembler.processEvent('content_block_start', {
          'index': index,
          'content_block': blockMap,
        });
        // Yield appropriate start update.
        if (block is ToolUseBlock) {
          yield ToolUseStart(
            toolName: block.name,
            toolId: block.id,
            blockIndex: index,
          );
        }

      case ContentBlockDeltaEvent(:final index, :final text):
        assembler.processEvent('content_block_delta', {
          'index': index,
          'delta': {'type': 'text_delta', 'text': text},
        });
        yield TextDelta(text: text, blockIndex: index);

      case ContentBlockStopEvent(:final index):
        assembler.processEvent('content_block_stop', {'index': index});

      case MessageDeltaEvent(:final stopReason, :final usage):
        final data = <String, dynamic>{
          'delta': {if (stopReason != null) 'stop_reason': stopReason.name},
        };
        if (usage != null) {
          data['usage'] = {'output_tokens': usage.outputTokens};
          yield UsageUpdate(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheCreationInputTokens: usage.cacheCreationInputTokens,
            cacheReadInputTokens: usage.cacheReadInputTokens,
          );
        }
        assembler.processEvent('message_delta', data);

      case MessageStopEvent():
        assembler.processEvent('message_stop', {});
        yield MessageComplete(
          stopReason: assembler.state.stopReason,
          messageId: assembler.state.messageId,
          model: assembler.state.model,
        );

      case ErrorEvent(:final message, :final type):
        yield StreamError(message: message, errorType: type);
    }
  }
}

Map<String, dynamic> _contentBlockToMap(ContentBlock block) => switch (block) {
  TextBlock(:final text) => {'type': 'text', 'text': text},
  ToolUseBlock(:final id, :final name, :final input) => {
    'type': 'tool_use',
    'id': id,
    'name': name,
    'input': input,
  },
  ImageBlock(:final mediaType, :final base64Data) => {
    'type': 'image',
    'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Data},
  },
  ToolResultBlock() => {'type': 'tool_result'},
};
