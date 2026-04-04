import 'package:flutter/material.dart';

import '../../domain/models/message.dart';
import 'message_renderer.dart';

/// Displays streaming text with a blinking cursor using the full MessageRenderer.
class StreamingText extends StatelessWidget {
  final String text;
  final String? toolName;

  const StreamingText({super.key, required this.text, this.toolName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Assistant',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              if (toolName != null) ...[
                const SizedBox(width: 8),
                _ToolIndicator(name: toolName!),
              ],
            ],
          ),
          const SizedBox(height: 4),
          text.isEmpty
              ? _ThinkingDots()
              : MessageRenderer(
                  block: TextBlock('$text\u258C'),
                ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: 4),
          Text(name, style: const TextStyle(fontSize: 10)),
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
