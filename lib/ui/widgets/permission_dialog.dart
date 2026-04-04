// Permission dialog — Flutter UI for tool permission prompts.
// Port of neom_claw's permission system UI components.

import 'package:flutter/material.dart';

import '../../domain/models/permissions.dart';

/// Result of a permission dialog.
class PermissionDialogResult {
  final bool allowed;
  final bool rememberForSession;
  final bool rememberForProject;

  const PermissionDialogResult({
    required this.allowed,
    this.rememberForSession = false,
    this.rememberForProject = false,
  });
}

/// Show a permission dialog for a tool use request.
/// Returns null if dismissed, otherwise the user's decision.
Future<PermissionDialogResult?> showPermissionDialog({
  required BuildContext context,
  required String toolName,
  required Map<String, dynamic> input,
  PermissionExplanation? explanation,
}) {
  return showDialog<PermissionDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PermissionDialogWidget(
      toolName: toolName,
      input: input,
      explanation: explanation,
    ),
  );
}

class _PermissionDialogWidget extends StatefulWidget {
  final String toolName;
  final Map<String, dynamic> input;
  final PermissionExplanation? explanation;

  const _PermissionDialogWidget({
    required this.toolName,
    required this.input,
    this.explanation,
  });

  @override
  State<_PermissionDialogWidget> createState() =>
      _PermissionDialogWidgetState();
}

class _PermissionDialogWidgetState extends State<_PermissionDialogWidget> {
  bool _rememberSession = false;
  bool _rememberProject = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final explanation = widget.explanation;
    final riskColor = explanation != null
        ? _riskColor(explanation.riskLevel)
        : Colors.orange;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.security, color: riskColor, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Permission: ${widget.toolName}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (explanation != null) ...[
              _RiskBadge(
                riskLevel: explanation.riskLevel,
                title: explanation.title,
              ),
              const SizedBox(height: 8),
              Text(
                explanation.description,
                style: theme.textTheme.bodyMedium,
              ),
              const Divider(height: 24),
            ],
            // Tool input preview
            Text(
              'Tool Input:',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatInput(widget.input),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                maxLines: 15,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            // Remember options
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember for this session'),
              value: _rememberSession,
              onChanged: (v) => setState(() => _rememberSession = v ?? false),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember for this project'),
              value: _rememberProject,
              onChanged: (v) => setState(() {
                _rememberProject = v ?? false;
                if (_rememberProject) _rememberSession = true;
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            PermissionDialogResult(
              allowed: false,
              rememberForSession: _rememberSession,
              rememberForProject: _rememberProject,
            ),
          ),
          child: const Text('Deny'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            PermissionDialogResult(
              allowed: true,
              rememberForSession: _rememberSession,
              rememberForProject: _rememberProject,
            ),
          ),
          child: const Text('Allow'),
        ),
      ],
    );
  }

  String _formatInput(Map<String, dynamic> input) {
    final lines = <String>[];
    for (final entry in input.entries) {
      final value = entry.value;
      if (value is String && value.length > 200) {
        lines.add('${entry.key}: ${value.substring(0, 200)}...');
      } else {
        lines.add('${entry.key}: $value');
      }
    }
    return lines.join('\n');
  }

  Color _riskColor(RiskLevel level) => switch (level) {
        RiskLevel.low => Colors.green,
        RiskLevel.medium => Colors.orange,
        RiskLevel.high => Colors.red,
      };
}

class _RiskBadge extends StatelessWidget {
  final RiskLevel riskLevel;
  final String title;

  const _RiskBadge({required this.riskLevel, required this.title});

  @override
  Widget build(BuildContext context) {
    final color = switch (riskLevel) {
      RiskLevel.low => Colors.green,
      RiskLevel.medium => Colors.orange,
      RiskLevel.high => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (riskLevel) {
              RiskLevel.low => Icons.check_circle_outline,
              RiskLevel.medium => Icons.warning_amber,
              RiskLevel.high => Icons.dangerous,
            },
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '${riskLevel.name.toUpperCase()}: $title',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline permission banner — compact alternative to full dialog.
/// Used for lower-risk tool operations within the chat flow.
class PermissionBanner extends StatelessWidget {
  final String toolName;
  final String? description;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const PermissionBanner({
    super.key,
    required this.toolName,
    this.description,
    required this.onAllow,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.security, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Allow $toolName?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            TextButton(onPressed: onDeny, child: const Text('Deny')),
            const SizedBox(width: 4),
            FilledButton.tonal(
                onPressed: onAllow, child: const Text('Allow')),
          ],
        ),
      ),
    );
  }
}
