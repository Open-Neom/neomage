// TaskDetailViews — faithful port of neom_claw/src/components/tasks/
// Ports: ShellDetailDialog, AsyncAgentDetailDialog, RemoteSessionDetailDialog,
// InProcessTeammateDetailDialog, DreamDetailDialog, ShellProgress,
// RemoteSessionProgress, renderToolActivity, and related types.
//
// These are the per-task-type detail views that open from the
// BackgroundTasksDialog when the user selects a task and presses Enter.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import 'background_tasks_panel.dart';
import 'design_system.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const int _shellDetailTailBytes = 8192;
const String _diamondOpen = '\u25C7';
const String _diamondFilled = '\u25C6';

// ─── Tool activity rendering (port of renderToolActivity.tsx) ─────────────

/// Describes a tool use activity for display in task detail views.
class ToolActivity {
  final String toolName;
  final Map<String, dynamic> input;

  const ToolActivity({required this.toolName, this.input = const {}});
}

/// Format a tool use activity into a human-readable string.
/// Port of renderToolActivity() from renderToolActivity.tsx.
String renderToolActivity(ToolActivity activity) {
  final name = activity.toolName;
  final input = activity.input;

  // Try to extract a user-facing description from the input.
  for (final v in input.values) {
    if (v is String && v.trim().isNotEmpty) {
      final oneLine = v.replaceAll(RegExp(r'\s+'), ' ').trim();
      final truncated = oneLine.length > 60
          ? '${oneLine.substring(0, 57)}...'
          : oneLine;
      return '$name $truncated';
    }
  }
  return name;
}

/// Format a compact tool use summary for remote sessions.
/// Port of formatToolUseSummary() from RemoteSessionDetailDialog.tsx.
String formatToolUseSummary(String name, dynamic input) {
  if (name == 'ExitPlanModeTool') {
    return 'Review the plan in NeomClaw on the web';
  }
  if (input == null || input is! Map) return name;

  // AskUserQuestion: show the question text
  if (name == 'AskUserQuestion' && input.containsKey('questions')) {
    final qs = input['questions'];
    if (qs is List && qs.isNotEmpty && qs[0] is Map) {
      final q = qs[0]['question'] as String? ?? qs[0]['header'] as String?;
      if (q != null && q.isNotEmpty) {
        final oneLine = q.replaceAll(RegExp(r'\s+'), ' ').trim();
        final truncated = oneLine.length > 50
            ? '${oneLine.substring(0, 47)}...'
            : oneLine;
        return 'Answer in browser: $truncated';
      }
    }
  }

  for (final v in (input).values) {
    if (v is String && v.trim().isNotEmpty) {
      final oneLine = v.replaceAll(RegExp(r'\s+'), ' ').trim();
      final truncated = oneLine.length > 60
          ? '${oneLine.substring(0, 57)}...'
          : oneLine;
      return '$name $truncated';
    }
  }
  return name;
}

// ─── Task output result ──────────────────────────────────────────────────────

class TaskOutputResult {
  final String content;
  final int bytesTotal;

  const TaskOutputResult({required this.content, required this.bytesTotal});

  static const empty = TaskOutputResult(content: '', bytesTotal: 0);
}

// ─── TaskStatusText widget (port of ShellProgress.tsx TaskStatusText) ─────

class TaskStatusTextWidget extends StatelessWidget {
  final TaskStatus status;
  final String? label;
  final String? suffix;

  const TaskStatusTextWidget({
    super.key,
    required this.status,
    this.label,
    this.suffix,
  });

  Color _color(BuildContext context) {
    switch (status) {
      case TaskStatus.completed:
        return ClawColors.success;
      case TaskStatus.failed:
        return ClawColors.error;
      case TaskStatus.killed:
        return ClawColors.warning;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ?? status.name;
    return Text(
      '($displayLabel${suffix ?? ''})',
      style: TextStyle(
        color: _color(context).withValues(alpha: 0.7),
        fontSize: 13,
      ),
    );
  }
}

// ─── ShellProgress widget (port of ShellProgress.tsx) ────────────────────

class ShellProgressWidget extends StatelessWidget {
  final BackgroundTaskState shell;

  const ShellProgressWidget({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    switch (shell.status) {
      case TaskStatus.completed:
        return const TaskStatusTextWidget(
          status: TaskStatus.completed,
          label: 'done',
        );
      case TaskStatus.failed:
        return const TaskStatusTextWidget(
          status: TaskStatus.failed,
          label: 'error',
        );
      case TaskStatus.killed:
        return const TaskStatusTextWidget(
          status: TaskStatus.killed,
          label: 'stopped',
        );
      case TaskStatus.running:
      case TaskStatus.pending:
        return const TaskStatusTextWidget(status: TaskStatus.running);
    }
  }
}

// ─── RemoteSessionProgress widget (port of RemoteSessionProgress.tsx) ────

class RemoteSessionProgressWidget extends StatelessWidget {
  final BackgroundTaskState session;

  const RemoteSessionProgressWidget({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final running =
        session.status == TaskStatus.running ||
        session.status == TaskStatus.pending;
    final statusText = running ? 'running' : session.status.name;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          running ? Icons.play_arrow : Icons.check_circle,
          size: 14,
          color: running ? ClawColors.info : ClawColors.success,
        ),
        const SizedBox(width: 4),
        Text(
          statusText,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ─── ShellDetailDialog controller ────────────────────────────────────────

class ShellDetailController extends SintController {
  final BackgroundTaskState shell;
  final VoidCallback onDone;
  final VoidCallback? onKillShell;
  final VoidCallback? onBack;

  ShellDetailController({
    required this.shell,
    required this.onDone,
    this.onKillShell,
    this.onBack,
  });

  final output = Rxn<TaskOutputResult>();
  final isLoadingOutput = true.obs;
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    _loadOutput();
    if (shell.status == TaskStatus.running) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _loadOutput(),
      );
    }
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  Future<void> _loadOutput() async {
    isLoadingOutput.value = true;
    try {
      // In a real implementation, this would read the task output file.
      // For now, we provide a placeholder that mirrors the TS behavior.
      output.value = TaskOutputResult(
        content: shell.summary ?? 'No output available',
        bytesTotal: shell.summary?.length ?? 0,
      );
    } catch (_) {
      output.value = TaskOutputResult.empty;
    } finally {
      isLoadingOutput.value = false;
    }
  }

  void handleKeyAction(String key) {
    switch (key) {
      case 'space':
        onDone();
        break;
      case 'left':
        if (onBack != null) onBack!();
        break;
      case 'x':
        if (shell.status == TaskStatus.running && onKillShell != null) {
          onKillShell!();
        }
        break;
    }
  }
}

// ─── ShellDetailDialog widget (port of ShellDetailDialog.tsx) ────────────

class ShellDetailDialog extends StatelessWidget {
  final BackgroundTaskState shell;
  final VoidCallback onDone;
  final VoidCallback? onKillShell;
  final VoidCallback? onBack;

  const ShellDetailDialog({
    super.key,
    required this.shell,
    required this.onDone,
    this.onKillShell,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Sint.put(
      ShellDetailController(
        shell: shell,
        onDone: onDone,
        onKillShell: onKillShell,
        onBack: onBack,
      ),
      tag: 'shell-${shell.id}',
    );

    final theme = Theme.of(context);
    final displayCommand = shell.kind == 'monitor'
        ? shell.description
        : (shell.command ?? shell.description);
    final elapsedDuration = DateTime.now().difference(shell.startTime);
    final elapsedText = _formatDuration(elapsedDuration);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title bar ──
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (onBack != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shell Detail',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDone,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Command ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ClawColors.codeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayCommand,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: ClawColors.codeText,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 12),

            // ── Status row ──
            Row(
              children: [
                ShellProgressWidget(shell: shell),
                const SizedBox(width: 8),
                Text(
                  elapsedText,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Output ──
            Expanded(
              child: Obx(() {
                final result = controller.output.value;
                if (controller.isLoadingOutput.value && result == null) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final content = result?.content ?? '';
                final bytesTotal = result?.bytesTotal ?? 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bytesTotal > _shellDetailTailBytes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Showing last ${_formatFileSize(_shellDetailTailBytes)}'
                          ' of ${_formatFileSize(bytesTotal)}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ClawColors.codeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            content,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: ClawColors.codeText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),

            const SizedBox(height: 12),

            // ── Actions bar ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (shell.status == TaskStatus.running && onKillShell != null)
                  TextButton.icon(
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Stop'),
                    style: TextButton.styleFrom(
                      foregroundColor: ClawColors.error,
                    ),
                    onPressed: onKillShell,
                  ),
                const SizedBox(width: 8),
                TextButton(onPressed: onDone, child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AsyncAgentDetailDialog controller ───────────────────────────────────

class AsyncAgentDetailController extends SintController {
  final BackgroundTaskState agent;
  final VoidCallback onDone;
  final VoidCallback? onKillAgent;
  final VoidCallback? onBack;

  AsyncAgentDetailController({
    required this.agent,
    required this.onDone,
    this.onKillAgent,
    this.onBack,
  });

  final elapsedTime = ''.obs;
  Timer? _elapsedTimer;

  @override
  void onInit() {
    super.onInit();
    _updateElapsed();
    if (agent.status == TaskStatus.running) {
      _elapsedTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateElapsed(),
      );
    }
  }

  @override
  void onClose() {
    _elapsedTimer?.cancel();
    super.onClose();
  }

  void _updateElapsed() {
    final duration = DateTime.now().difference(agent.startTime);
    elapsedTime.value = _formatDuration(duration);
  }

  void handleKeyAction(String key) {
    switch (key) {
      case 'space':
        onDone();
        break;
      case 'left':
        if (onBack != null) onBack!();
        break;
      case 'x':
        if (agent.status == TaskStatus.running && onKillAgent != null) {
          onKillAgent!();
        }
        break;
    }
  }
}

// ─── AsyncAgentDetailDialog widget (port of AsyncAgentDetailDialog.tsx) ──

class AsyncAgentDetailDialog extends StatelessWidget {
  final BackgroundTaskState agent;
  final VoidCallback onDone;
  final VoidCallback? onKillAgent;
  final VoidCallback? onBack;

  const AsyncAgentDetailDialog({
    super.key,
    required this.agent,
    required this.onDone,
    this.onKillAgent,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Sint.put(
      AsyncAgentDetailController(
        agent: agent,
        onDone: onDone,
        onKillAgent: onKillAgent,
        onBack: onBack,
      ),
      tag: 'agent-${agent.id}',
    );

    final theme = Theme.of(context);
    final agentType = 'agent';
    final displayPrompt = agent.description.length > 300
        ? '${agent.description.substring(0, 297)}...'
        : agent.description;

    final statusIcon = getTaskStatusIcon(
      agent.status,
      hasError: agent.hasError,
      awaitingApproval: agent.awaitingApproval,
      shutdownRequested: agent.shutdownRequested,
      isIdle: agent.isIdle,
    );
    final statusColor = getTaskStatusColor(
      agent.status,
      hasError: agent.hasError,
      awaitingApproval: agent.awaitingApproval,
      shutdownRequested: agent.shutdownRequested,
      isIdle: agent.isIdle,
    );

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ──
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (onBack != null) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$agentType > ${agent.description.isEmpty ? "Async agent" : agent.description}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDone,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Status + elapsed ──
            Row(
              children: [
                if (agent.status != TaskStatus.running) ...[
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    agent.status == TaskStatus.completed
                        ? 'Completed'
                        : agent.status == TaskStatus.failed
                        ? 'Failed'
                        : 'Stopped',
                    style: TextStyle(color: statusColor, fontSize: 13),
                  ),
                  const Text(' \u00B7 ', style: TextStyle(fontSize: 13)),
                ],
                Obx(
                  () => Text(
                    controller.elapsedTime.value,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Prompt ──
            Text(
              'Prompt:',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ClawColors.codeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayPrompt,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: ClawColors.codeText,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Progress info ──
            if (agent.progress != null) ...[
              _buildProgressRow(
                'Last activity',
                agent.progress!.lastActivityDescription ?? 'working',
              ),
              if (agent.progress!.recentActivities != null &&
                  agent.progress!.recentActivities!.isNotEmpty)
                _buildProgressRow(
                  'Recent',
                  agent.progress!.recentActivities!.take(3).join(', '),
                ),
            ],

            const Spacer(),

            // ── Actions bar ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (agent.status == TaskStatus.running && onKillAgent != null)
                  TextButton.icon(
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Stop'),
                    style: TextButton.styleFrom(
                      foregroundColor: ClawColors.error,
                    ),
                    onPressed: onKillAgent,
                  ),
                const SizedBox(width: 8),
                TextButton(onPressed: onDone, child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── RemoteSessionDetailDialog controller ────────────────────────────────

class RemoteSessionDetailController extends SintController {
  final BackgroundTaskState session;
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final VoidCallback? onKill;

  RemoteSessionDetailController({
    required this.session,
    required this.onDone,
    this.onBack,
    this.onKill,
  });

  final elapsedTime = ''.obs;
  Timer? _elapsedTimer;

  @override
  void onInit() {
    super.onInit();
    _updateElapsed();
    final running =
        session.status == TaskStatus.running ||
        session.status == TaskStatus.pending;
    if (running) {
      _elapsedTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateElapsed(),
      );
    }
  }

  @override
  void onClose() {
    _elapsedTimer?.cancel();
    super.onClose();
  }

  void _updateElapsed() {
    final duration = DateTime.now().difference(session.startTime);
    elapsedTime.value = _formatDuration(duration);
  }
}

// ─── RemoteSessionDetailDialog widget ────────────────────────────────────

class RemoteSessionDetailDialog extends StatelessWidget {
  final BackgroundTaskState session;
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final VoidCallback? onKill;

  const RemoteSessionDetailDialog({
    super.key,
    required this.session,
    required this.onDone,
    this.onBack,
    this.onKill,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Sint.put(
      RemoteSessionDetailController(
        session: session,
        onDone: onDone,
        onBack: onBack,
        onKill: onKill,
      ),
      tag: 'remote-${session.id}',
    );

    final theme = Theme.of(context);
    final running =
        session.status == TaskStatus.running ||
        session.status == TaskStatus.pending;
    final diamond = running ? _diamondOpen : _diamondFilled;
    final displayTitle = (session.title ?? session.description).length > 60
        ? '${(session.title ?? session.description).substring(0, 57)}...'
        : (session.title ?? session.description);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ──
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: onBack ?? () => onDone(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (onBack != null) const SizedBox(width: 8),
                Text(
                  diamond,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDone,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Status + elapsed ──
            Row(
              children: [
                RemoteSessionProgressWidget(session: session),
                const SizedBox(width: 8),
                Obx(
                  () => Text(
                    controller.elapsedTime.value,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Session ID ──
            if (session.sessionId != null) ...[
              Row(
                children: [
                  Text(
                    'Session: ',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      session.sessionId!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // ── Review info for remote reviews ──
            if (session.isRemoteReview)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ClawColors.infoBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: ClawColors.info.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.rate_review, size: 16, color: ClawColors.info),
                    const SizedBox(width: 8),
                    const Text(
                      'Remote review session',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),

            // ── Ultraplan info ──
            if (session.isUltraplan)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ClawColors.warningBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: ClawColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree,
                        size: 16,
                        color: ClawColors.warning,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Ultraplan session',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

            const Spacer(),

            // ── Actions ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (running && onKill != null)
                  TextButton.icon(
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Stop'),
                    style: TextButton.styleFrom(
                      foregroundColor: ClawColors.error,
                    ),
                    onPressed: onKill,
                  ),
                const SizedBox(width: 8),
                TextButton(onPressed: onDone, child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── InProcessTeammateDetailDialog controller ────────────────────────────

class TeammateDetailController extends SintController {
  final BackgroundTaskState teammate;
  final VoidCallback onDone;
  final VoidCallback? onKill;
  final VoidCallback? onBack;
  final VoidCallback? onForeground;

  TeammateDetailController({
    required this.teammate,
    required this.onDone,
    this.onKill,
    this.onBack,
    this.onForeground,
  });

  final elapsedTime = ''.obs;
  Timer? _elapsedTimer;

  @override
  void onInit() {
    super.onInit();
    _updateElapsed();
    if (teammate.status == TaskStatus.running) {
      _elapsedTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateElapsed(),
      );
    }
  }

  @override
  void onClose() {
    _elapsedTimer?.cancel();
    super.onClose();
  }

  void _updateElapsed() {
    final duration = DateTime.now().difference(teammate.startTime);
    elapsedTime.value = _formatDuration(duration);
  }
}

// ─── InProcessTeammateDetailDialog widget ────────────────────────────────

class InProcessTeammateDetailDialog extends StatelessWidget {
  final BackgroundTaskState teammate;
  final VoidCallback onDone;
  final VoidCallback? onKill;
  final VoidCallback? onBack;
  final VoidCallback? onForeground;

  const InProcessTeammateDetailDialog({
    super.key,
    required this.teammate,
    required this.onDone,
    this.onKill,
    this.onBack,
    this.onForeground,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Sint.put(
      TeammateDetailController(
        teammate: teammate,
        onDone: onDone,
        onKill: onKill,
        onBack: onBack,
        onForeground: onForeground,
      ),
      tag: 'teammate-${teammate.id}',
    );

    final theme = Theme.of(context);
    final identity = teammate.identity;
    final agentName = identity?.agentName ?? 'teammate';
    final agentColor = identity?.color ?? ClawColors.info;

    // Derive activity text (port of describeTeammateActivity)
    final activity = _describeTeammateActivity(teammate);

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ──
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (onBack != null) const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: agentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '@$agentName',
                    style: TextStyle(
                      color: agentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    teammate.description,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDone,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Status + activity ──
            Row(
              children: [
                Icon(
                  teammate.isIdle
                      ? Icons.more_horiz
                      : teammate.awaitingApproval
                      ? Icons.help_outline
                      : Icons.play_arrow,
                  size: 16,
                  color: teammate.isIdle
                      ? theme.colorScheme.onSurfaceVariant
                      : teammate.awaitingApproval
                      ? ClawColors.warning
                      : ClawColors.success,
                ),
                const SizedBox(width: 6),
                Obx(
                  () => Text(
                    '${controller.elapsedTime.value} \u00B7 $activity',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Progress details ──
            if (teammate.progress != null) ...[
              if (teammate.progress!.lastActivityDescription != null)
                _buildInfoRow(
                  'Current',
                  teammate.progress!.lastActivityDescription!,
                ),
              if (teammate.progress!.recentActivities != null &&
                  teammate.progress!.recentActivities!.isNotEmpty)
                ..._buildRecentActivities(
                  teammate.progress!.recentActivities!,
                  theme,
                ),
            ],

            const Spacer(),

            // ── Actions ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onForeground != null &&
                    teammate.status == TaskStatus.running)
                  TextButton.icon(
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Foreground'),
                    onPressed: onForeground,
                  ),
                if (onKill != null &&
                    teammate.status == TaskStatus.running) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Stop'),
                    style: TextButton.styleFrom(
                      foregroundColor: ClawColors.error,
                    ),
                    onPressed: onKill,
                  ),
                ],
                const SizedBox(width: 8),
                TextButton(onPressed: onDone, child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRecentActivities(
    List<String> activities,
    ThemeData theme,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(
          'Recent Activities:',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      ...activities
          .take(5)
          .map(
            (a) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Row(
                children: [
                  const Text('\u2022 ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Text(
                      a,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
    ];
  }
}

// ─── DreamDetailDialog (port of DreamDetailDialog.tsx) ───────────────────

class DreamDetailDialog extends StatelessWidget {
  final BackgroundTaskState task;
  final VoidCallback onDone;
  final VoidCallback? onBack;
  final VoidCallback? onKill;

  const DreamDetailDialog({
    super.key,
    required this.task,
    required this.onDone,
    this.onBack,
    this.onKill,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = task.status == TaskStatus.running;
    final elapsed = _formatDuration(DateTime.now().difference(task.startTime));

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ──
            Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (onBack != null) const SizedBox(width: 8),
                const Icon(Icons.auto_fix_high, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Dream Task',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDone,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Description ──
            Text(task.description, style: const TextStyle(fontSize: 14)),

            const SizedBox(height: 12),

            // ── Status ──
            Row(
              children: [
                Icon(
                  running ? Icons.play_arrow : Icons.check_circle,
                  size: 16,
                  color: running ? ClawColors.info : ClawColors.success,
                ),
                const SizedBox(width: 6),
                Text(
                  running ? 'Running' : task.status.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: running ? ClawColors.info : ClawColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  elapsed,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // ── Actions ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (running && onKill != null)
                  TextButton.icon(
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Stop'),
                    style: TextButton.styleFrom(
                      foregroundColor: ClawColors.error,
                    ),
                    onPressed: onKill,
                  ),
                const SizedBox(width: 8),
                TextButton(onPressed: onDone, child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Utility: getTaskStatusIcon ──────────────────────────────────────────

/// Returns the appropriate icon for a task based on status and state flags.
/// Port of getTaskStatusIcon() from taskStatusUtils.tsx.
IconData getTaskStatusIcon(
  TaskStatus status, {
  bool isIdle = false,
  bool awaitingApproval = false,
  bool hasError = false,
  bool shutdownRequested = false,
}) {
  if (hasError) return Icons.close;
  if (awaitingApproval) return Icons.help_outline;
  if (shutdownRequested) return Icons.warning_amber;
  if (status == TaskStatus.running) {
    if (isIdle) return Icons.more_horiz;
    return Icons.play_arrow;
  }
  if (status == TaskStatus.completed) return Icons.check;
  if (status == TaskStatus.failed || status == TaskStatus.killed) {
    return Icons.close;
  }
  return Icons.circle;
}

/// Returns the appropriate semantic color for a task based on status and flags.
/// Port of getTaskStatusColor() from taskStatusUtils.tsx.
Color getTaskStatusColor(
  TaskStatus status, {
  bool isIdle = false,
  bool awaitingApproval = false,
  bool hasError = false,
  bool shutdownRequested = false,
}) {
  if (hasError) return ClawColors.error;
  if (awaitingApproval) return ClawColors.warning;
  if (shutdownRequested) return ClawColors.warning;
  if (isIdle) return ClawColors.darkTextTertiary;
  if (status == TaskStatus.completed) return ClawColors.success;
  if (status == TaskStatus.failed) return ClawColors.error;
  if (status == TaskStatus.killed) return ClawColors.warning;
  return ClawColors.darkTextTertiary;
}

/// Returns true if the given task status is terminal (finished).
/// Port of isTerminalStatus() from taskStatusUtils.tsx.
bool isTerminalStatus(TaskStatus status) {
  return status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.killed;
}

// ─── Utility: describeTeammateActivity ───────────────────────────────────

/// Derives a human-readable activity string for an in-process teammate.
/// Port of describeTeammateActivity() from taskStatusUtils.tsx.
String _describeTeammateActivity(BackgroundTaskState t) {
  if (t.shutdownRequested) return 'stopping';
  if (t.awaitingApproval) return 'awaiting approval';
  if (t.isIdle) return 'idle';

  if (t.progress != null) {
    final recentSummary =
        (t.progress!.recentActivities != null &&
            t.progress!.recentActivities!.isNotEmpty)
        ? t.progress!.recentActivities!.take(3).join(', ')
        : null;
    if (recentSummary != null && recentSummary.isNotEmpty) {
      return recentSummary;
    }
    if (t.progress!.lastActivityDescription != null) {
      return t.progress!.lastActivityDescription!;
    }
  }
  return 'working';
}

// ─── Utility: shouldHideTasksFooter ──────────────────────────────────────

/// Returns true when BackgroundTaskStatus would render nothing because the
/// spinner tree is active and every visible background task is an in-process
/// teammate. Port of shouldHideTasksFooter() from taskStatusUtils.tsx.
bool shouldHideTasksFooter(
  Map<String, BackgroundTaskState> tasks,
  bool showSpinnerTree,
) {
  if (!showSpinnerTree) return false;
  bool hasVisibleTask = false;
  for (final t in tasks.values) {
    hasVisibleTask = true;
    if (t.type != BackgroundTaskType.inProcessTeammate) return false;
  }
  return hasVisibleTask;
}

// ─── Formatting helpers ──────────────────────────────────────────────────

String _formatDuration(Duration d) {
  if (d.inHours > 0) {
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
  return '${d.inSeconds}s';
}

String _formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
