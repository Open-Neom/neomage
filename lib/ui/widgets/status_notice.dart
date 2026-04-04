// Status notices and slow operation tracking — comprehensive port of
// neom_claw/src/utils/statusNoticeDefinitions.tsx,
// neom_claw/src/utils/status.tsx, and
// neom_claw/src/utils/slowOperations.ts.
// Provides status property building, notice definitions, and slow operation
// instrumentation for performance monitoring.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

// ════════════════════════════════════════════════════════════════════════════
// Slow operation tracking infrastructure
// ════════════════════════════════════════════════════════════════════════════

/// Threshold in milliseconds for logging slow operations.
/// Operations taking longer than this are logged for debugging.
const int defaultSlowOperationThresholdMs = 300;

/// A recorded slow operation.
class SlowOperation {
  final String description;
  final double durationMs;
  final DateTime timestamp;

  const SlowOperation({
    required this.description,
    required this.durationMs,
    required this.timestamp,
  });

  @override
  String toString() => '$description (${durationMs.toStringAsFixed(1)}ms)';
}

/// Extract the first useful stack frame outside the slow operations module.
String callerFrame(StackTrace? stack) {
  if (stack == null) return '';
  final lines = stack.toString().split('\n');
  for (final line in lines) {
    if (line.contains('status_notice.dart')) continue;
    final match = RegExp(r'([^/\\]+?):(\d+):\d+\)?$').firstMatch(line);
    if (match != null) return ' @ ${match.group(1)}:${match.group(2)}';
  }
  return '';
}

/// Build a human-readable description from tagged arguments.
String buildSlowDescription(String template, List<dynamic> args) {
  var result = template;
  for (var i = 0; i < args.length; i++) {
    final v = args[i];
    String replacement;
    if (v is List) {
      replacement = 'List[${v.length}]';
    } else if (v is Map) {
      replacement = 'Map{${v.length} keys}';
    } else if (v is String) {
      replacement = v.length > 80 ? '${v.substring(0, 80)}...' : v;
    } else {
      replacement = '$v';
    }
    result = result.replaceFirst('{$i}', replacement);
  }
  return result;
}

/// A disposable timer for measuring slow operations.
/// Use with try/finally to ensure proper cleanup.
class SlowOperationTimer {
  final String description;
  final int thresholdMs;
  final void Function(SlowOperation)? onSlow;
  final Stopwatch _stopwatch = Stopwatch();
  final StackTrace _capturedStack;
  bool _disposed = false;

  SlowOperationTimer({
    required this.description,
    this.thresholdMs = defaultSlowOperationThresholdMs,
    this.onSlow,
  }) : _capturedStack = StackTrace.current {
    _stopwatch.start();
  }

  /// Stop the timer and check if the operation was slow.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopwatch.stop();
    final duration = _stopwatch.elapsedMilliseconds.toDouble();
    if (duration > thresholdMs) {
      final fullDescription = '$description${callerFrame(_capturedStack)}';
      final op = SlowOperation(
        description: fullDescription,
        durationMs: duration,
        timestamp: DateTime.now(),
      );
      onSlow?.call(op);
    }
  }
}

/// Global slow operation tracker.
class SlowOperationTracker {
  static final SlowOperationTracker instance = SlowOperationTracker._();

  SlowOperationTracker._();

  final _operations = <SlowOperation>[];
  int _thresholdMs = defaultSlowOperationThresholdMs;
  bool _isLogging = false;

  /// All recorded slow operations.
  List<SlowOperation> get operations => List.unmodifiable(_operations);

  /// Current threshold.
  int get thresholdMs => _thresholdMs;

  /// Update the threshold.
  set thresholdMs(int value) {
    if (value >= 0) _thresholdMs = value;
  }

  /// Record a slow operation.
  void addSlowOperation(String description, double durationMs) {
    if (_isLogging) return; // Prevent re-entrancy.
    _isLogging = true;
    try {
      _operations.add(
        SlowOperation(
          description: description,
          durationMs: durationMs,
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      _isLogging = false;
    }
  }

  /// Create a timer for tracking a potentially slow operation.
  SlowOperationTimer track(String description) {
    return SlowOperationTimer(
      description: description,
      thresholdMs: _thresholdMs,
      onSlow: (op) => addSlowOperation(op.description, op.durationMs),
    );
  }

  /// Clear all recorded operations.
  void clear() => _operations.clear();

  /// Get recent operations (last N).
  List<SlowOperation> recent([int count = 10]) {
    if (_operations.length <= count) return List.unmodifiable(_operations);
    return List.unmodifiable(_operations.sublist(_operations.length - count));
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Status property types
// ════════════════════════════════════════════════════════════════════════════

/// A single property in the status display.
class StatusProperty {
  final String? label;
  final dynamic value; // String, Widget, or List<String>

  const StatusProperty({this.label, required this.value});
}

/// A diagnostic message in the status display.
class StatusDiagnostic {
  final String message;
  final bool isWarning;

  const StatusDiagnostic({required this.message, this.isWarning = false});
}

// ════════════════════════════════════════════════════════════════════════════
// Status notice types
// ════════════════════════════════════════════════════════════════════════════

/// Type of status notice.
enum StatusNoticeType { warning, info }

/// Context for evaluating status notices.
class StatusNoticeContext {
  final Map<String, dynamic> config;
  final List<MemoryFileInfo> memoryFiles;
  final int? agentDescriptionTokens;
  final String? authTokenSource;
  final String? apiKeySource;
  final bool isSubscriber;

  const StatusNoticeContext({
    required this.config,
    this.memoryFiles = const [],
    this.agentDescriptionTokens,
    this.authTokenSource,
    this.apiKeySource,
    this.isSubscriber = false,
  });
}

/// Information about a memory file (NEOMCLAW.md etc.).
class MemoryFileInfo {
  final String path;
  final String content;

  const MemoryFileInfo({required this.path, required this.content});

  /// Whether the file exceeds the size threshold.
  bool get isLarge => content.length > maxMemoryCharacterCount;
}

/// Maximum character count before a memory file is considered large.
const int maxMemoryCharacterCount = 50000;

/// Threshold for total agent description tokens.
const int agentDescriptionsThreshold = 10000;

/// Get memory files that exceed the size threshold.
List<MemoryFileInfo> getLargeMemoryFiles(List<MemoryFileInfo> files) =>
    files.where((f) => f.isLarge).toList();

/// A definition of a status notice.
class StatusNoticeDefinition {
  final String id;
  final StatusNoticeType type;
  final bool Function(StatusNoticeContext) isActive;
  final Widget Function(StatusNoticeContext, BuildContext) render;

  const StatusNoticeDefinition({
    required this.id,
    required this.type,
    required this.isActive,
    required this.render,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// Notice definitions
// ════════════════════════════════════════════════════════════════════════════

/// Large memory files notice.
final StatusNoticeDefinition largeMemoryFilesNotice = StatusNoticeDefinition(
  id: 'large-memory-files',
  type: StatusNoticeType.warning,
  isActive: (ctx) => getLargeMemoryFiles(ctx.memoryFiles).isNotEmpty,
  render: (ctx, context) {
    final theme = Theme.of(context);
    final largeFiles = getLargeMemoryFiles(ctx.memoryFiles);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: largeFiles.map((file) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Large '),
                      TextSpan(
                        text: _displayPath(file.path),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(
                        text:
                            ' will impact performance (${_formatNumber(file.content.length)} chars'
                            ' > ${_formatNumber(maxMemoryCharacterCount)})',
                      ),
                      TextSpan(
                        text: ' \u00B7 /memory to edit',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  },
);

/// Auth conflict: subscriber using external token.
final StatusNoticeDefinition
subscriberExternalTokenNotice = StatusNoticeDefinition(
  id: 'neomclaw-ai-external-token',
  type: StatusNoticeType.warning,
  isActive: (ctx) =>
      ctx.isSubscriber &&
      (ctx.authTokenSource == 'ANTHROPIC_AUTH_TOKEN' ||
          ctx.authTokenSource == 'apiKeyHelper'),
  render: (ctx, context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Auth conflict: Using ${ctx.authTokenSource} instead of NeomClaw account '
              'subscription token. Either unset ${ctx.authTokenSource}, or run '
              '`neomclaw /logout`.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  },
);

/// Auth conflict: API key overriding config key.
final StatusNoticeDefinition apiKeyConflictNotice = StatusNoticeDefinition(
  id: 'api-key-conflict',
  type: StatusNoticeType.warning,
  isActive: (ctx) =>
      ctx.apiKeySource != null &&
      ctx.apiKeySource != 'none' &&
      (ctx.apiKeySource == 'ANTHROPIC_API_KEY' ||
          ctx.apiKeySource == 'apiKeyHelper'),
  render: (ctx, context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Auth conflict: Using ${ctx.apiKeySource} instead of Anthropic Console key. '
              'Either unset ${ctx.apiKeySource}, or run `neomclaw /logout`.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  },
);

/// Both auth methods set at once.
final StatusNoticeDefinition bothAuthMethodsNotice = StatusNoticeDefinition(
  id: 'both-auth-methods',
  type: StatusNoticeType.warning,
  isActive: (ctx) =>
      ctx.apiKeySource != null &&
      ctx.apiKeySource != 'none' &&
      ctx.authTokenSource != null &&
      ctx.authTokenSource != 'none' &&
      !(ctx.apiKeySource == 'apiKeyHelper' &&
          ctx.authTokenSource == 'apiKeyHelper'),
  render: (ctx, context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Auth conflict: Both a token (${ctx.authTokenSource}) and an API key '
                  '(${ctx.apiKeySource}) are set. This may lead to unexpected behavior.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\u00B7 Trying to use ${ctx.authTokenSource == "neomclaw.ai" ? "neomclaw.ai" : ctx.authTokenSource}? '
                  '${ctx.apiKeySource == "ANTHROPIC_API_KEY" ? "Unset the ANTHROPIC_API_KEY environment variable." : "neomclaw /logout"}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
                Text(
                  '\u00B7 Trying to use ${ctx.apiKeySource}? '
                  '${ctx.authTokenSource == "neomclaw.ai" ? "neomclaw /logout to sign out of neomclaw.ai." : "Unset the ${ctx.authTokenSource} environment variable."}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  },
);

/// Large cumulative agent descriptions.
final StatusNoticeDefinition
largeAgentDescriptionsNotice = StatusNoticeDefinition(
  id: 'large-agent-descriptions',
  type: StatusNoticeType.warning,
  isActive: (ctx) =>
      (ctx.agentDescriptionTokens ?? 0) > agentDescriptionsThreshold,
  render: (ctx, context) {
    final theme = Theme.of(context);
    final tokens = ctx.agentDescriptionTokens ?? 0;
    return Row(
      children: [
        Icon(Icons.warning_amber, size: 16, color: theme.colorScheme.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text:
                      'Large cumulative agent descriptions will impact performance '
                      '(~${_formatNumber(tokens)} tokens > '
                      '${_formatNumber(agentDescriptionsThreshold)})',
                ),
                TextSpan(
                  text: ' \u00B7 /agents to manage',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  },
);

/// All notice definitions.
final List<StatusNoticeDefinition> statusNoticeDefinitions = [
  largeMemoryFilesNotice,
  largeAgentDescriptionsNotice,
  subscriberExternalTokenNotice,
  apiKeyConflictNotice,
  bothAuthMethodsNotice,
];

/// Get currently active notices for a given context.
List<StatusNoticeDefinition> getActiveNotices(StatusNoticeContext context) {
  return statusNoticeDefinitions.where((n) => n.isActive(context)).toList();
}

// ════════════════════════════════════════════════════════════════════════════
// Status property builders
// ════════════════════════════════════════════════════════════════════════════

/// Build account properties for the status display.
List<StatusProperty> buildAccountProperties({
  String? subscription,
  String? tokenSource,
  String? apiKeySource,
  String? organization,
  String? email,
  bool isDemoMode = false,
}) {
  final properties = <StatusProperty>[];
  if (subscription != null) {
    properties.add(
      StatusProperty(label: 'Login method', value: '$subscription Account'),
    );
  }
  if (tokenSource != null) {
    properties.add(StatusProperty(label: 'Auth token', value: tokenSource));
  }
  if (apiKeySource != null) {
    properties.add(StatusProperty(label: 'API key', value: apiKeySource));
  }
  if (organization != null && !isDemoMode) {
    properties.add(StatusProperty(label: 'Organization', value: organization));
  }
  if (email != null && !isDemoMode) {
    properties.add(StatusProperty(label: 'Email', value: email));
  }
  return properties;
}

/// Build API provider properties.
List<StatusProperty> buildApiProviderProperties({
  required String apiProvider,
  String? baseUrl,
  String? region,
  String? gcpProject,
  bool skipAuth = false,
}) {
  final properties = <StatusProperty>[];
  if (apiProvider != 'firstParty') {
    final label = switch (apiProvider) {
      'bedrock' => 'AWS Bedrock',
      'vertex' => 'Google Vertex AI',
      'foundry' => 'Microsoft Foundry',
      _ => apiProvider,
    };
    properties.add(StatusProperty(label: 'API provider', value: label));
  }
  if (baseUrl != null) {
    final urlLabel = switch (apiProvider) {
      'bedrock' => 'Bedrock base URL',
      'vertex' => 'Vertex base URL',
      _ => 'Anthropic base URL',
    };
    properties.add(StatusProperty(label: urlLabel, value: baseUrl));
  }
  if (region != null) {
    final regionLabel = apiProvider == 'bedrock'
        ? 'AWS region'
        : 'Default region';
    properties.add(StatusProperty(label: regionLabel, value: region));
  }
  if (gcpProject != null) {
    properties.add(StatusProperty(label: 'GCP project', value: gcpProject));
  }
  if (skipAuth) {
    properties.add(
      StatusProperty(value: '${apiProvider.toUpperCase()} auth skipped'),
    );
  }
  return properties;
}

/// Build model properties.
List<StatusProperty> buildModelProperties({
  required String modelDisplay,
  String? defaultModelDescription,
}) {
  final properties = <StatusProperty>[
    StatusProperty(label: 'Model', value: modelDisplay),
  ];
  if (defaultModelDescription != null) {
    properties.add(
      StatusProperty(label: 'Default model', value: defaultModelDescription),
    );
  }
  return properties;
}

/// Build MCP server properties (summary).
List<StatusProperty> buildMcpProperties({
  int connected = 0,
  int pending = 0,
  int needsAuth = 0,
  int failed = 0,
}) {
  if (connected + pending + needsAuth + failed == 0) return [];
  final parts = <String>[];
  if (connected > 0) parts.add('$connected connected');
  if (needsAuth > 0) parts.add('$needsAuth need auth');
  if (pending > 0) parts.add('$pending pending');
  if (failed > 0) parts.add('$failed failed');
  return [
    StatusProperty(
      label: 'MCP servers',
      value: '${parts.join(", ")} \u00B7 /mcp',
    ),
  ];
}

/// Build setting sources properties.
List<StatusProperty> buildSettingSourcesProperties(List<String> sourceNames) {
  if (sourceNames.isEmpty) return [];
  return [StatusProperty(label: 'Setting sources', value: sourceNames)];
}

/// Build sandbox properties.
List<StatusProperty> buildSandboxProperties({required bool isEnabled}) {
  return [
    StatusProperty(
      label: 'Bash Sandbox',
      value: isEnabled ? 'Enabled' : 'Disabled',
    ),
  ];
}

/// Build memory diagnostics.
List<StatusDiagnostic> buildMemoryDiagnostics(List<MemoryFileInfo> files) {
  final largeFiles = getLargeMemoryFiles(files);
  return largeFiles.map((file) {
    final displayPath = _displayPath(file.path);
    return StatusDiagnostic(
      message:
          'Large $displayPath will impact performance (${_formatNumber(file.content.length)} chars > ${_formatNumber(maxMemoryCharacterCount)})',
      isWarning: true,
    );
  }).toList();
}

// ════════════════════════════════════════════════════════════════════════════
// StatusNoticeController — reactive state with Sint
// ════════════════════════════════════════════════════════════════════════════

/// Controller for status notices and slow operation monitoring.
class StatusNoticeController extends SintController {
  final activeNotices = <StatusNoticeDefinition>[].obs;
  final diagnostics = <StatusDiagnostic>[].obs;
  final properties = <StatusProperty>[].obs;
  final slowOperations = <SlowOperation>[].obs;
  final isExpanded = false.obs;

  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    // Periodically refresh slow operations.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refreshSlowOperations(),
    );
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  /// Evaluate notices against the given context and update state.
  void evaluateNotices(StatusNoticeContext context) {
    activeNotices.value = getActiveNotices(context);
  }

  /// Refresh slow operations from the tracker.
  void refreshSlowOperations() {
    slowOperations.value = SlowOperationTracker.instance.recent(20);
  }

  /// Toggle expanded state.
  void toggleExpanded() => isExpanded.value = !isExpanded.value;

  /// Whether there are any warnings.
  bool get hasWarnings =>
      activeNotices.any((n) => n.type == StatusNoticeType.warning);

  /// Whether there are any info notices.
  bool get hasInfo => activeNotices.any((n) => n.type == StatusNoticeType.info);

  /// Total notice count.
  int get noticeCount => activeNotices.length;
}

// ════════════════════════════════════════════════════════════════════════════
// StatusNoticeView widget
// ════════════════════════════════════════════════════════════════════════════

/// Widget that renders active status notices.
class StatusNoticeView extends StatelessWidget {
  final StatusNoticeContext noticeContext;

  const StatusNoticeView({super.key, required this.noticeContext});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<StatusNoticeController>();

    return Obx(() {
      final notices = controller.activeNotices;
      if (notices.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: notices
            .map((notice) => notice.render(noticeContext, context))
            .toList(),
      );
    });
  }
}

/// Widget that renders a slow operations debug panel.
class SlowOperationsPanel extends StatelessWidget {
  const SlowOperationsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<StatusNoticeController>();
    final theme = Theme.of(context);

    return Obx(() {
      final ops = controller.slowOperations;
      if (ops.isEmpty) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.speed, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  'Slow Operations (${ops.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...ops.map(
              (op) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${op.durationMs.toStringAsFixed(0)}ms',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        op.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Utility helpers
// ════════════════════════════════════════════════════════════════════════════

/// Format a number with comma separators.
String _formatNumber(int n) {
  if (n < 1000) return '$n';
  final str = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
}

/// Get a display-friendly path (shorten home directory).
String _displayPath(String path) {
  // In a real implementation, this would relativize against cwd.
  final parts = path.split('/');
  if (parts.length > 3) {
    return '.../${parts.sublist(parts.length - 2).join('/')}';
  }
  return path;
}
