import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum MessageRole { user, assistant, system }

enum StopReason { endTurn, maxTokens, toolUse, stopSequence }

/// A content block within a message — mirrors Anthropic's content block types.
sealed class ContentBlock {
  const ContentBlock();
}

class TextBlock extends ContentBlock {
  final String text;
  const TextBlock(this.text);
}

class ToolUseBlock extends ContentBlock {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  const ToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
  });
}

class ToolResultBlock extends ContentBlock {
  final String toolUseId;
  final String content;
  final bool isError;
  const ToolResultBlock({
    required this.toolUseId,
    required this.content,
    this.isError = false,
  });
}

class ImageBlock extends ContentBlock {
  final String mediaType;
  final String base64Data;
  const ImageBlock({required this.mediaType, required this.base64Data});
}

/// A single message in the conversation.
class Message {
  final String id;
  final MessageRole role;
  final List<ContentBlock> content;
  final DateTime timestamp;
  final StopReason? stopReason;
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

class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;

  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
    inputTokens: json['input_tokens'] as int? ?? 0,
    outputTokens: json['output_tokens'] as int? ?? 0,
    cacheCreationInputTokens: json['cache_creation_input_tokens'] as int?,
    cacheReadInputTokens: json['cache_read_input_tokens'] as int?,
  );

  int get totalTokens => inputTokens + outputTokens;
}
