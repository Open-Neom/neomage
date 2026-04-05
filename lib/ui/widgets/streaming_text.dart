import 'package:flutter/material.dart';

import 'package:neomage/domain/models/message.dart';
import 'message_renderer.dart';

/// Displays streaming text aligned left (assistant style) with a blinking cursor.
class StreamingText extends StatelessWidget {
  final String text;
  final String? toolName;

  const StreamingText({super.key, required this.text, this.toolName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth < 600
        ? screenWidth * 0.82
        : screenWidth * 0.65;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(top: 8, bottom: 4, right: 48, left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (toolName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ToolIndicator(name: toolName!),
              ),
            text.isEmpty
                ? _ThinkingDots()
                : MessageRenderer(
                    block: TextBlock('$text\u258C'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _ToolIndicator extends StatelessWidget {
  final String name;
  const _ToolIndicator({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final dots = '.' * ((_controller.value * 3).floor() + 1);
        return Text(
          'Thinking$dots',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        );
      },
    );
  }
}
