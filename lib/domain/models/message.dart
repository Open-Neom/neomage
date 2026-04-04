import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// The role of a message sender in the conversation.
enum MessageRole {
  /// A human user message.
  user,

  /// An AI assistant response.
  assistant,

  /// A system-level instruction.
  system,
}

/// Reason the model stopped generating output.
enum StopReason {
  /// The model finished its response naturally.
  endTurn,

  /// The response was truncated due to token limits.
  maxTokens,

  /// The model invoked a tool and awaits the result.
  toolUse,

  /// A stop sequence was encountered.
  stopSequence,
}

/// A content block within a message — mirrors Anthropic's content block types.
sealed class ContentBlock {
  const ContentBlock();
}

/// A plain text content block.
class TextBlock extends ContentBlock {
  /// The text content.
  final String text;
  const TextBlock(this.text);
}

/// A tool invocation content block.
class ToolUseBlock extends ContentBlock {
  /// Unique identifier for this tool call.
  final String id;

  /// Name of the tool being invoked.
  final String name;

  /// JSON input parameters for the tool.
  final Map<String, dynamic> input;
  const ToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
  });
}

/// The result returned from a tool execution.
class ToolResultBlock extends ContentBlock {
  /// The ID of the tool call this result corresponds to.
  final String toolUseId;

  /// The textual output from the tool.
  final String content;

  /// Whether the tool execution resulted in an error.
  final bool isError;
  const ToolResultBlock({
    required this.toolUseId,
    required this.content,
    this.isError = false,
  });
}

/// A base64-encoded image content block.
class ImageBlock extends ContentBlock {
  /// MIME type of the image (e.g., 'image/png').
  final String mediaType;

  /// Base64-encoded image data.
  final String base64Data;
  const ImageBlock({required this.mediaType, required this.base64Data});
}

/// A single message in the conversation.
class Message {
  /// Unique identifier for this message.
  final String id;

  /// The role of the message sender.
  final MessageRole role;

  /// Content blocks containing text, images, or tool interactions.
  final List<ContentBlock> content;

  /// When this message was created.
  final DateTime timestamp;

  /// Why the model stopped generating (assistant messages only).
  final StopReason? stopReason;

  /// Token usage statistics (assistant messages only).
  final TokenUsage? usage;

  Message({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.stopReason,
    this.usage,
  }) : id = id ?? _uuid.v4(),
       timestamp = timestamp ?? DateTime.now();

  /// Convenience: extract all text from content blocks.
  String get textContent =>
      content.whereType<TextBlock>().map((b) => b.text).join('\n');

  /// Convenience: extract all tool use blocks.
  List<ToolUseBlock> get toolUses => content.whereType<ToolUseBlock>().toList();

  /// Create a simple text message.
  factory Message.user(String text) =>
      Message(role: MessageRole.user, content: [TextBlock(text)]);

  /// Create a simple text message from the assistant.
  factory Message.assistant(String text) =>
      Message(role: MessageRole.assistant, content: [TextBlock(text)]);

  /// Convert to Anthropic API format.
  Map<String, dynamic> toApiMap() => {
    'role': role == MessageRole.user ? 'user' : 'assistant',
    'content': content.map(_contentBlockToMap).toList(),
  };

  static Map<String, dynamic> _contentBlockToMap(ContentBlock block) =>
      switch (block) {
        TextBlock(text: final t) => {'type': 'text', 'text': t},
        ToolUseBlock(id: final id, name: final n, input: final i) => {
          'type': 'tool_use',
          'id': id,
          'name': n,
          'input': i,
        },
        ToolResultBlock(
          toolUseId: final tid,
          content: final c,
          isError: final e,
        ) =>
          {
            'type': 'tool_result',
            'tool_use_id': tid,
            'content': c,
            if (e) 'is_error': true,
          },
        ImageBlock(mediaType: final m, base64Data: final d) => {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': m, 'data': d},
        },
      };
}

/// Token usage statistics for an API call.
class TokenUsage {
  /// Number of input tokens consumed.
  final int inputTokens;

  /// Number of output tokens generated.
  final int outputTokens;

  /// Tokens used to create a new cache entry (Anthropic prompt caching).
  final int? cacheCreationInputTokens;

  /// Tokens read from an existing cache entry (Anthropic prompt caching).
  final int? cacheReadInputTokens;

  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });

  /// Deserialize from an API JSON response.
  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
    inputTokens: json['input_tokens'] as int? ?? 0,
    outputTokens: json['output_tokens'] as int? ?? 0,
    cacheCreationInputTokens: json['cache_creation_input_tokens'] as int?,
    cacheReadInputTokens: json['cache_read_input_tokens'] as int?,
  );

  /// Total tokens (input + output).
  int get totalTokens => inputTokens + outputTokens;
}
