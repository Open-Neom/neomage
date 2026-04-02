// Tool output widget — renders tool results in the chat stream.
// Shows tool name, input summary, output content, and error styling.

import 'package:flutter/material.dart';

/// Widget for displaying a tool use and its result in the chat flow.
class ToolOutputWidget extends StatefulWidget {
  final String toolName;
  final Map<String, dynamic> input;
  final String output;
  final bool isError;
  final bool initiallyExpanded;

  const ToolOutputWidget({
    super.key,
    required this.toolName,
    required this.input,
    required this.output,
    this.isError = false,
    this.initiallyExpanded = false,
  });

  @override
  State<ToolOutputWidget> createState() => _ToolOutputWidgetState();
}

class _ToolOutputWidgetState extends State<ToolOutputWidget> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded || widget.isError;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: widget.isError
          ? (isDark ? const Color(0xFF3D1212) : const Color(0xFFFEECEC))
          : theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    _toolIcon(widget.toolName),
                    size: 16,
                    color: widget.isError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.toolName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: widget.isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inputSummary(widget.toolName, widget.input),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              // Output (expanded)
              if (_expanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 300),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.output,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _toolIcon(String name) => switch (name) {
        'Read' => Icons.description_outlined,
        'Write' => Icons.edit_document,
        'Edit' => Icons.edit,
        'Bash' => Icons.terminal,
        'Grep' => Icons.search,
        'Glob' => Icons.folder_open,
        'Agent' => Icons.smart_toy,
        'WebSearch' => Icons.travel_explore,
        'WebFetch' => Icons.cloud_download,
        'TodoWrite' => Icons.checklist,
        'ToolSearch' => Icons.extension_outlined,
        _ => Icons.build,
      };

  String _inputSummary(String toolName, Map<String, dynamic> input) {
    return switch (toolName) {
      'Read' => input['file_path'] as String? ?? '',
      'Write' => input['file_path'] as String? ?? '',
      'Edit' => input['file_path'] as String? ?? '',
      'Bash' => input['command'] as String? ?? '',
      'Grep' => '/${input['pattern'] ?? ''}/',
      'Glob' => input['pattern'] as String? ?? '',
      'Agent' => input['description'] as String? ?? '',
      'WebSearch' => input['query'] as String? ?? '',
      'WebFetch' => input['url'] as String? ?? '',
      _ => input.keys.take(2).join(', '),
    };
  }
}

/// Widget for showing tool execution progress (spinner + tool name).
class ToolProgressIndicator extends StatelessWidget {
  final String toolName;
  final String? description;

  const ToolProgressIndicator({
    super.key,
    required this.toolName,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            description ?? 'Using $toolName...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
