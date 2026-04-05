// TrustDialog — port of neomage/src/components/TrustDialog/
// Ports: TrustDialog.tsx, utils.ts
//
// Displays a trust/security confirmation dialog when entering a new project
// directory. Shows which project-level settings are active that could
// execute code: hooks, bash permissions, MCP servers, API key helpers,
// AWS/GCP commands, otel headers, dangerous env vars.
//
// The user must accept or exit before proceeding.

import 'package:neomage/core/platform/neomage_io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

import '../../utils/constants/neomage_translation_constants.dart';

// ─── Trust setting source model (mirrors utils.ts) ───

/// Represents a project setting source that needs trust approval.
class TrustSettingSource {
  final String filePath;
  final TrustSettingType type;

  const TrustSettingSource({required this.filePath, required this.type});
}

enum TrustSettingType {
  hooks,
  bashPermission,
  apiKeyHelper,
  awsCommands,
  gcpCommands,
  otelHeaders,
  dangerousEnvVars,
  mcpServer,
  slashCommandBash,
  skillsBash,
}

// ─── Trust dialog utils (mirrors TrustDialog/utils.ts) ───

/// Format a list of items with proper "and" conjunction.
String formatListWithAnd(List<String> items, {int limit = 0}) {
  if (items.isEmpty) return '';

  final effectiveLimit = limit == 0 ? null : limit;

  // No limit or within limit: normal formatting
  if (effectiveLimit == null || items.length <= effectiveLimit) {
    if (items.length == 1) return items[0];
    if (items.length == 2) return '${items[0]} and ${items[1]}';

    final lastItem = items.last;
    final allButLast = items.sublist(0, items.length - 1);
    return '${allButLast.join(', ')}, and $lastItem';
  }

  // More items than limit: show first few + count
  final shown = items.sublist(0, effectiveLimit);
  final remaining = items.length - effectiveLimit;

  if (shown.length == 1) {
    return '${shown[0]} and $remaining more';
  }

  return '${shown.join(', ')}, and $remaining more';
}

// ─── TrustDialogController (SintController) ───

class TrustDialogController extends SintController {
  // Observable state
  final hasTrustAccepted = false.obs;
  final isHomeDir = false.obs;

  // Setting sources detected
  final hooksSources = <TrustSettingSource>[].obs;
  final bashPermissionSources = <TrustSettingSource>[].obs;
  final apiKeyHelperSources = <TrustSettingSource>[].obs;
  final awsCommandsSources = <TrustSettingSource>[].obs;
  final gcpCommandsSources = <TrustSettingSource>[].obs;
  final otelHeadersSources = <TrustSettingSource>[].obs;
  final dangerousEnvVarsSources = <TrustSettingSource>[].obs;
  final mcpServerNames = <String>[].obs;

  // Slash command / skills bash
  final hasSlashCommandBash = false.obs;
  final hasSkillsBash = false.obs;

  // Computed
  bool get hasHooks => hooksSources.isNotEmpty;
  bool get hasBashPermission => bashPermissionSources.isNotEmpty;
  bool get hasApiKeyHelper => apiKeyHelperSources.isNotEmpty;
  bool get hasAwsCommands => awsCommandsSources.isNotEmpty;
  bool get hasGcpCommands => gcpCommandsSources.isNotEmpty;
  bool get hasOtelHeaders => otelHeadersSources.isNotEmpty;
  bool get hasDangerousEnvVars => dangerousEnvVarsSources.isNotEmpty;
  bool get hasMcpServers => mcpServerNames.isNotEmpty;

  bool get hasAnyBashExecution =>
      hasBashPermission || hasSlashCommandBash.value || hasSkillsBash.value;

  bool get hasAnyConcern =>
      hasHooks ||
      hasAnyBashExecution ||
      hasMcpServers ||
      hasApiKeyHelper ||
      hasAwsCommands ||
      hasGcpCommands ||
      hasOtelHeaders ||
      hasDangerousEnvVars;

  /// The list of security concern descriptions to show.
  List<TrustConcernItem> get concerns {
    final items = <TrustConcernItem>[];

    if (hasAnyBashExecution) {
      final sources = <String>[];
      for (final s in bashPermissionSources) {
        sources.add(s.filePath);
      }
      if (hasSlashCommandBash.value) sources.add('slash commands');
      if (hasSkillsBash.value) sources.add('skills');

      items.add(
        TrustConcernItem(
          icon: Icons.terminal,
          title: 'Bash command execution',
          description: 'Project settings allow running shell commands',
          sources: sources,
          severity: TrustConcernSeverity.high,
        ),
      );
    }

    if (hasMcpServers) {
      items.add(
        TrustConcernItem(
          icon: Icons.dns,
          title: 'MCP servers',
          description:
              'Project configures ${mcpServerNames.length} MCP ${mcpServerNames.length == 1 ? 'server' : 'servers'}: '
              '${formatListWithAnd(mcpServerNames, limit: 3)}',
          sources: const ['.neomage/settings.json'],
          severity: TrustConcernSeverity.medium,
        ),
      );
    }

    if (hasHooks) {
      final sources = hooksSources.map((s) => s.filePath).toList();
      items.add(
        TrustConcernItem(
          icon: Icons.webhook,
          title: 'Hooks',
          description: 'Project settings configure hooks that run commands',
          sources: sources,
          severity: TrustConcernSeverity.high,
        ),
      );
    }

    if (hasApiKeyHelper) {
      final sources = apiKeyHelperSources.map((s) => s.filePath).toList();
      items.add(
        TrustConcernItem(
          icon: Icons.key,
          title: 'API key helper',
          description: 'Project settings configure an API key helper command',
          sources: sources,
          severity: TrustConcernSeverity.high,
        ),
      );
    }

    if (hasAwsCommands) {
      final sources = awsCommandsSources.map((s) => s.filePath).toList();
      items.add(
        TrustConcernItem(
          icon: Icons.cloud,
          title: 'AWS commands',
          description: 'Project settings configure AWS credential commands',
          sources: sources,
          severity: TrustConcernSeverity.medium,
        ),
      );
    }

    if (hasGcpCommands) {
      final sources = gcpCommandsSources.map((s) => s.filePath).toList();
      items.add(
        TrustConcernItem(
          icon: Icons.cloud,
          title: 'GCP commands',
          description: 'Project settings configure GCP auth commands',
          sources: sources,
          severity: TrustConcernSeverity.medium,
        ),
      );
    }

    if (hasOtelHeaders) {
      final sources = otelHeadersSources.map((s) => s.filePath).toList();
      items.add(
        TrustConcernItem(
          icon: Icons.analytics,
          title: 'OpenTelemetry headers helper',
          description: 'Project settings configure an OTEL headers helper',
          sources: sources,
          severity: TrustConcernSeverity.low,
        ),
      );
    }

    if (hasDangerousEnvVars) {
      final sources = dangerousEnvVarsSources.map((s) => s.filePath).toList();
      items.add(
        TrustConcernItem(
          icon: Icons.warning_amber,
          title: 'Environment variables',
          description:
              'Project settings set environment variables that may be sensitive',
          sources: sources,
          severity: TrustConcernSeverity.medium,
        ),
      );
    }

    return items;
  }

  @override
  void onInit() {
    super.onInit();
    // Check if running in home directory
    isHomeDir.value = Platform.environment['HOME'] == Directory.current.path;
  }

  /// Accept trust and proceed.
  void accept() {
    hasTrustAccepted.value = true;
    // In real implementation, this would persist the trust decision
    // to .neomage/settings.local.json
  }
}

// ─── Trust concern models ───

enum TrustConcernSeverity { low, medium, high }

class TrustConcernItem {
  final IconData icon;
  final String title;
  final String description;
  final List<String> sources;
  final TrustConcernSeverity severity;

  const TrustConcernItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.sources,
    required this.severity,
  });
}

// ─── TrustDialog widget (mirrors TrustDialog.tsx) ───

class TrustDialog extends StatelessWidget {
  final VoidCallback onDone;

  const TrustDialog({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<TrustDialogController>();

    return Obx(() {
      // If already accepted, auto-proceed
      if (controller.hasTrustAccepted.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onDone());
        return const SizedBox.shrink();
      }

      return _TrustDialogContent(controller: controller, onDone: onDone);
    });
  }
}

class _TrustDialogContent extends StatelessWidget {
  final TrustDialogController controller;
  final VoidCallback onDone;

  const _TrustDialogContent({required this.controller, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final concerns = controller.concerns;
    final cwd = Directory.current.path;

    // Get display path (shorten home dir)
    final homeDir = Platform.environment['HOME'] ?? '';
    final displayPath = cwd.startsWith(homeDir)
        ? '~${cwd.substring(homeDir.length)}'
        : cwd;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            // Exit
            exit(1);
          }
        }
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _TrustDialogHeader(displayPath: displayPath),

                const Divider(height: 1),

                // Warning message
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.orange.withValues(alpha: 0.05),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This project has settings that allow code execution. '
                          'Only proceed if you trust this project.',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Concerns list
                if (concerns.isNotEmpty) ...[
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: concerns
                            .map((c) => _TrustConcernTile(concern: c))
                            .toList(),
                      ),
                    ),
                  ),
                ],

                // No concerns fallback
                if (!controller.hasAnyConcern) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No security concerns detected in project settings.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],

                const Divider(height: 1),

                // Action buttons
                _TrustDialogActions(controller: controller, onDone: onDone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Header ───

class _TrustDialogHeader extends StatelessWidget {
  final String displayPath;

  const _TrustDialogHeader({required this.displayPath});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Trust this project?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            displayPath,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Concern tile ───

class _TrustConcernTile extends StatelessWidget {
  final TrustConcernItem concern;

  const _TrustConcernTile({required this.concern});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final severityColor = switch (concern.severity) {
      TrustConcernSeverity.high => Colors.red[700]!,
      TrustConcernSeverity.medium => Colors.orange[700]!,
      TrustConcernSeverity.low => Colors.blue[700]!,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(concern.icon, size: 16, color: severityColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  concern.title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  concern.description,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                if (concern.sources.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: concern.sources.map((source) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.05,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          source,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Action buttons ───

class _TrustDialogActions extends StatelessWidget {
  final TrustDialogController controller;
  final VoidCallback onDone;

  const _TrustDialogActions({required this.controller, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Exit button
          OutlinedButton(
            onPressed: () => exit(1),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(
                color: theme.colorScheme.error.withValues(alpha: 0.5),
              ),
            ),
            child: Text(NeomageTranslationConstants.exit.tr),
          ),

          const SizedBox(width: 12),

          // Trust & Continue button
          FilledButton.icon(
            onPressed: () {
              controller.accept();
              onDone();
            },
            icon: const Icon(Icons.check, size: 16),
            label: Text(NeomageTranslationConstants.trustAndContinue.tr),
          ),
        ],
      ),
    );
  }
}
