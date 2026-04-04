import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../domain/models/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Role label
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(
                isUser ? 'You' : 'Assistant',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // Message content
            Card(
              color: isUser
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: message.content.map(_buildBlock).toList(),
                ),
              ),
            ),
            // Token usage
            if (message.usage != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  '${message.usage!.inputTokens} in / ${message.usage!.outputTokens} out',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(ContentBlock block) => switch (block) {
    TextBlock(text: final text) => MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        codeblockDecoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        code: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 13,
          color: Colors.greenAccent,
        ),
      ),
    ),
    ToolUseBlock(name: final name, input: final input) => _ToolUseChip(
      name: name,
      input: input,
    ),
    ToolResultBlock(content: final content, isError: final isError) =>
      _ToolResultCard(content: content, isError: isError),
    _ => const SizedBox.shrink(),
  };
}

class _ToolUseChip extends StatelessWidget {
  final String name;
  final Map<String, dynamic> input;

  const _ToolUseChip({required this.name, required this.input});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.build, size: 14, color: colorScheme.onTertiaryContainer),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolResultCard extends StatelessWidget {
  final String content;
  final bool isError;

  const _ToolResultCard({required this.content, required this.isError});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError ? Colors.red.withValues(alpha: 0.1) : Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: isError ? Border.all(color: Colors.red.shade300) : null,
      ),
      child: Text(
        content.length > 500 ? '${content.substring(0, 500)}...' : content,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 11,
          color: isError ? Colors.red.shade300 : Colors.white70,
        ),
      ),
    );
  }
}
