// SDK message adapter — ported from neomagent src/remote/sdkMessageAdapter.ts.
//
// Converts SDK-format messages received from the CCR WebSocket into the
// internal [Message] types used by the Flutter UI for rendering.

import 'dart:developer' as developer;

import 'package:neomage/data/remote/sessions_websocket.dart';
import 'package:neomage/domain/models/message.dart';

// ---------------------------------------------------------------------------
// Converted message result
// ---------------------------------------------------------------------------

/// Result of converting an SDK message from the remote session.
sealed class ConvertedMessage {
  const ConvertedMessage();
}

/// The SDK message was converted into a displayable [Message].
class ConvertedDisplayMessage extends ConvertedMessage {
  /// The converted message ready for rendering.
  final Message message;
  const ConvertedDisplayMessage(this.message);
}

/// The SDK message was a streaming event (partial assistant output).
class ConvertedStreamEvent extends ConvertedMessage {
  /// The raw streaming event payload.
  final Map<String, dynamic> event;
  const ConvertedStreamEvent(this.event);
}

/// The SDK message was intentionally ignored (already handled locally, or
/// not relevant for display).
class ConvertedIgnored extends ConvertedMessage {
  const ConvertedIgnored();
}

// ---------------------------------------------------------------------------
// Convert options
// ---------------------------------------------------------------------------

/// Options controlling which message types are converted vs ignored.
class ConvertOptions {
  /// Convert user messages containing `tool_result` content blocks into
  /// display messages. Used by direct-connect mode where tool results come
  /// from the remote server and need to be rendered locally. CCR mode ignores
  /// user messages since they are handled differently.
  final bool convertToolResults;

  /// Convert user text messages into display messages. Used when converting
  /// historical events where user-typed messages need to be shown. In live
  /// WS mode these are already added locally by the UI, so they are ignored
  /// by default.
  final bool convertUserTextMessages;

  /// Create conversion options.
  const ConvertOptions({
    this.convertToolResults = false,
    this.convertUserTextMessages = false,
  });
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

/// Convert an SDK assistant message to an internal [Message].
Message _convertAssistantMessage(SessionsMessage msg) {
  final apiMessage = msg.raw['message'] as Map<String, dynamic>?;
  final uuid = msg.raw['uuid'] as String?;
  final error = msg.raw['error'] as String?;

  final content = <ContentBlock>[];
  if (apiMessage != null) {
    final rawContent = apiMessage['content'] as List<dynamic>?;
    if (rawContent != null) {
      for (final block in rawContent) {
        if (block is Map<String, dynamic>) {
          final parsed = _parseContentBlock(block);
          if (parsed != null) content.add(parsed);
        }
      }
    }
  }

  // If there is an error, prepend it as text.
  if (error != null && error.isNotEmpty) {
    content.insert(0, TextBlock('[Error] $error'));
  }

  return Message(
    id: uuid,
    role: MessageRole.assistant,
    content: content,
  );
}

/// Parse a single content block from the API JSON.
ContentBlock? _parseContentBlock(Map<String, dynamic> block) {
  final type = block['type'] as String?;
  return switch (type) {
    'text' => TextBlock(block['text'] as String? ?? ''),
    'tool_use' => ToolUseBlock(
        id: block['id'] as String? ?? '',
        name: block['name'] as String? ?? '',
        input: block['input'] as Map<String, dynamic>? ?? {},
      ),
    'tool_result' => ToolResultBlock(
        toolUseId: block['tool_use_id'] as String? ?? '',
        content: block['content'] is String
            ? block['content'] as String
            : block['content']?.toString() ?? '',
        isError: block['is_error'] as bool? ?? false,
      ),
    _ => null,
  };
}

/// Convert an SDK result message to a system-level [Message].
Message? _convertResultMessage(SessionsMessage msg) {
  final subtype = msg.raw['subtype'] as String?;
  final isError = subtype != 'success';
  if (!isError) return null; // success results are noise

  final errors = msg.raw['errors'] as List<dynamic>?;
  final text =
      errors?.map((e) => e.toString()).join(', ') ?? 'Unknown error';

  return Message(
    id: msg.raw['uuid'] as String?,
    role: MessageRole.system,
    content: [TextBlock(text)],
  );
}

/// Convert an SDK init (system) message.
Message _convertInitMessage(SessionsMessage msg) {
  final model = msg.raw['model'] as String? ?? 'unknown';
  return Message(
    id: msg.raw['uuid'] as String?,
    role: MessageRole.system,
    content: [TextBlock('Remote session initialized (model: $model)')],
  );
}

/// Convert an SDK status message.
Message? _convertStatusMessage(SessionsMessage msg) {
  final status = msg.raw['status'] as String?;
  if (status == null) return null;

  final text = status == 'compacting'
      ? 'Compacting conversation\u2026'
      : 'Status: $status';

  return Message(
    id: msg.raw['uuid'] as String?,
    role: MessageRole.system,
    content: [TextBlock(text)],
  );
}

/// Convert an SDK tool progress message.
Message _convertToolProgressMessage(SessionsMessage msg) {
  final toolName = msg.raw['tool_name'] as String? ?? '';
  final elapsed = msg.raw['elapsed_time_seconds'] as num? ?? 0;

  return Message(
    id: msg.raw['uuid'] as String?,
    role: MessageRole.system,
    content: [TextBlock('Tool $toolName running for ${elapsed}s\u2026')],
  );
}

/// Convert an SDK compact-boundary message.
Message _convertCompactBoundaryMessage(SessionsMessage msg) {
  return Message(
    id: msg.raw['uuid'] as String?,
    role: MessageRole.system,
    content: [const TextBlock('Conversation compacted')],
  );
}

/// Build a user [Message] from raw content.
Message _buildUserMessage(SessionsMessage msg) {
  final rawContent = (msg.raw['message'] as Map<String, dynamic>?)?['content'];
  final content = <ContentBlock>[];

  if (rawContent is String) {
    content.add(TextBlock(rawContent));
  } else if (rawContent is List) {
    for (final block in rawContent) {
      if (block is Map<String, dynamic>) {
        final parsed = _parseContentBlock(block);
        if (parsed != null) content.add(parsed);
      }
    }
  }

  return Message(
    id: msg.raw['uuid'] as String?,
    role: MessageRole.user,
    content: content,
  );
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Convert a [SessionsMessage] (SDK format) to a [ConvertedMessage].
///
/// The CCR backend sends SDK-format messages via WebSocket. The Flutter UI
/// expects internal [Message] types for rendering. This function bridges the
/// two.
ConvertedMessage convertSDKMessage(
  SessionsMessage msg, {
  ConvertOptions options = const ConvertOptions(),
}) {
  switch (msg.type) {
    case 'assistant':
      return ConvertedDisplayMessage(_convertAssistantMessage(msg));

    case 'user':
      final rawContent =
          (msg.raw['message'] as Map<String, dynamic>?)?['content'];
      final isToolResult = rawContent is List &&
          rawContent.any(
            (b) => b is Map<String, dynamic> && b['type'] == 'tool_result',
          );

      if (options.convertToolResults && isToolResult) {
        return ConvertedDisplayMessage(_buildUserMessage(msg));
      }
      if (options.convertUserTextMessages && !isToolResult) {
        return ConvertedDisplayMessage(_buildUserMessage(msg));
      }
      return const ConvertedIgnored();

    case 'stream_event':
      final event = msg.raw['event'] as Map<String, dynamic>? ?? msg.raw;
      return ConvertedStreamEvent(event);

    case 'result':
      final converted = _convertResultMessage(msg);
      return converted != null
          ? ConvertedDisplayMessage(converted)
          : const ConvertedIgnored();

    case 'system':
      final subtype = msg.raw['subtype'] as String?;
      return switch (subtype) {
        'init' => ConvertedDisplayMessage(_convertInitMessage(msg)),
        'status' => () {
            final m = _convertStatusMessage(msg);
            return m != null
                ? ConvertedDisplayMessage(m)
                : const ConvertedIgnored();
          }(),
        'compact_boundary' =>
          ConvertedDisplayMessage(_convertCompactBoundaryMessage(msg)),
        _ => () {
            developer.log(
              'Ignoring system message subtype: $subtype',
              name: 'sdkMessageAdapter',
            );
            return const ConvertedIgnored();
          }(),
      };

    case 'tool_progress':
      return ConvertedDisplayMessage(_convertToolProgressMessage(msg));

    case 'auth_status':
    case 'tool_use_summary':
    case 'rate_limit_event':
      developer.log(
        'Ignoring ${msg.type} message',
        name: 'sdkMessageAdapter',
      );
      return const ConvertedIgnored();

    default:
      developer.log(
        'Unknown message type: ${msg.type}',
        name: 'sdkMessageAdapter',
      );
      return const ConvertedIgnored();
  }
}

/// Whether a [SessionsMessage] indicates the session has ended.
bool isSessionEndMessage(SessionsMessage msg) => msg.type == 'result';

/// Whether a result message indicates success.
bool isSuccessResult(SessionsMessage msg) =>
    msg.type == 'result' && msg.raw['subtype'] == 'success';

/// Extract the result text from a successful result message.
String? getResultText(SessionsMessage msg) {
  if (msg.raw['subtype'] == 'success') {
    return msg.raw['result'] as String?;
  }
  return null;
}
