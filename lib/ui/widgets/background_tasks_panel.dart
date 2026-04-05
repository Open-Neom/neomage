// BackgroundTasksPanel — port of neomage/src/components/tasks/
// Ports: BackgroundTasksDialog, BackgroundTask, BackgroundTaskStatus,
// ShellProgress, taskStatusUtils, renderToolActivity.
//
// Provides a full background-tasks management panel:
// - Task list grouped by type (teammates, shells, monitors, remote agents, local agents, workflows, dreams)
// - Detail dialogs for each task type
// - Task status pills/bar for the footer
// - Kill / foreground / stop actions
// - Keyboard navigation (up/down/enter/esc/x/f)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

import '../../utils/constants/neomage_translation_constants.dart';

// ─── Task status enum (mirrors TaskStatus in Task.ts) ───

enum TaskStatus { pending, running, completed, failed, killed }

// ─── Task types (mirrors the union type in tasks/types.ts) ───

enum BackgroundTaskType {
  localBash,
  remoteAgent,
  localAgent,
  inProcessTeammate,
  localWorkflow,
  monitorMcp,
  dream,
}

// ─── Task state model (mirrors BackgroundTaskState) ───

class BackgroundTaskState {
  final String id;
  final BackgroundTaskType type;
  final TaskStatus status;
  final String description;
  final String? command;
  final String? title;
  final String? summary;
  final DateTime startTime;
  final bool isIdle;
  final bool awaitingApproval;
  final bool shutdownRequested;
  final bool hasError;
  final bool notified;
  final bool isRemoteReview;
  final bool isUltraplan;
  final String? sessionId;
  final TeammateIdentity? identity;
  final TaskProgress? progress;
  final String? kind; // 'monitor' for bash monitor tasks

  const BackgroundTaskState({
    required this.id,
    required this.type,
    required this.status,
    required this.description,
    this.command,
    this.title,
    this.summary,
    required this.startTime,
    this.isIdle = false,
    this.awaitingApproval = false,
    this.shutdownRequested = false,
    this.hasError = false,
    this.notified = true,
    this.isRemoteReview = false,
    this.isUltraplan = false,
    this.sessionId,
    this.identity,
    this.progress,
    this.kind,
  });

  bool get isTerminal =>
      status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.killed;

  bool get isRunning => status == TaskStatus.running;
}

// ─── Teammate identity ───

class TeammateIdentity {
  final String agentName;
  final Color color;

  const TeammateIdentity({required this.agentName, required this.color});
}

// ─── Task progress ───

class TaskProgress {
  final String? lastActivityDescription;
  final List<String>? recentActivities;

  const TaskProgress({this.lastActivityDescription, this.recentActivities});
}

// ─── ListItem model (mirrors ListItem union in BackgroundTasksDialog) ───

class TaskListItem {
  final String id;
  final BackgroundTaskType? type; // null for 'leader' pseudo-item
  final String label;
  final TaskStatus status;
  final BackgroundTaskState? task;
  final bool isLeader;

  const TaskListItem({
    required this.id,
    this.type,
    required this.label,
    required this.status,
    this.task,
    this.isLeader = false,
  });

  factory TaskListItem.leader({String name = 'main'}) => TaskListItem(
    id: '__leader__',
    label: '@$name',
    status: TaskStatus.running,
    isLeader: true,
  );
}

// ─── taskStatusUtils (mirrors taskStatusUtils.tsx) ───

/// Returns true if the given task status represents a terminal (finished) state.
bool isTerminalStatus(TaskStatus status) {
  return status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.killed;
}

/// Returns the appropriate icon for a task based on status and state flags.
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

/// Returns the appropriate semantic color for a task based on status and state flags.
Color getTaskStatusColor(
  BuildContext context,
  TaskStatus status, {
  bool isIdle = false,
  bool awaitingApproval = false,
  bool hasError = false,
  bool shutdownRequested = false,
}) {
  final theme = Theme.of(context);
  if (hasError) return theme.colorScheme.error;
  if (awaitingApproval) return Colors.orange;
  if (shutdownRequested) return Colors.orange;
  if (isIdle) return theme.colorScheme.onSurface.withValues(alpha: 0.5);
  if (status == TaskStatus.completed) return Colors.green;
  if (status == TaskStatus.failed) return theme.colorScheme.error;
  if (status == TaskStatus.killed) return Colors.orange;
  return theme.colorScheme.onSurface.withValues(alpha: 0.5);
}

/// Derives a human-readable activity string for an in-process teammate.
String describeTeammateActivity(BackgroundTaskState task) {
  if (task.shutdownRequested) return 'stopping';
  if (task.awaitingApproval) return 'awaiting approval';
  if (task.isIdle) return 'idle';

  final activities = task.progress?.recentActivities;
  if (activities != null && activities.isNotEmpty) {
    return _summarizeRecentActivities(activities);
  }

  return task.progress?.lastActivityDescription ?? 'working';
}

/// Summarize recent activities into a single string.
String _summarizeRecentActivities(List<String> activities) {
  if (activities.isEmpty) return 'working';
  if (activities.length == 1) return activities.first;
  // Collapse duplicate activities
  final unique = activities.toSet().toList();
  if (unique.length == 1) return '${unique.first} (x${activities.length})';
  return unique.take(2).join(', ');
}

/// Returns true when the background tasks footer should be hidden because
/// the spinner tree is active and every visible background task is a teammate.
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

/// Truncates a string to maxLen, appending ellipsis if truncated.
String _truncate(String text, int maxLen) {
  if (text.length <= maxLen) return text;
  if (maxLen <= 3) return text.substring(0, maxLen);
  return '${text.substring(0, maxLen - 1)}...';
}

// ─── TaskStatusText widget (mirrors ShellProgress.tsx -> TaskStatusText) ───

class TaskStatusText extends StatelessWidget {
  final TaskStatus status;
  final String? label;
  final String? suffix;

  const TaskStatusText({
    super.key,
    required this.status,
    this.label,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ?? status.name;
    final color = switch (status) {
      TaskStatus.completed => Colors.green,
      TaskStatus.failed => Theme.of(context).colorScheme.error,
      TaskStatus.killed => Colors.orange,
      _ => Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
    };
    return Text(
      '($displayLabel${suffix ?? ''})',
      style: TextStyle(color: color, fontSize: 12),
    );
  }
}

// ─── ShellProgress widget (mirrors ShellProgress.tsx) ───

class ShellProgress extends StatelessWidget {
  final BackgroundTaskState shell;

  const ShellProgress({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return switch (shell.status) {
      TaskStatus.completed => TaskStatusText(
        status: TaskStatus.completed,
        label: NeomageTranslationConstants.done.tr,
      ),
      TaskStatus.failed => TaskStatusText(
        status: TaskStatus.failed,
        label: NeomageTranslationConstants.error.tr,
      ),
      TaskStatus.killed => TaskStatusText(
        status: TaskStatus.killed,
        label: NeomageTranslationConstants.stopped.tr,
      ),
      TaskStatus.running ||
      TaskStatus.pending => const TaskStatusText(status: TaskStatus.running),
    };
  }
}

// ─── BackgroundTaskItem widget (mirrors BackgroundTask.tsx) ───

class BackgroundTaskItem extends StatelessWidget {
  final BackgroundTaskState task;
  final int maxActivityWidth;

  const BackgroundTaskItem({
    super.key,
    required this.task,
    this.maxActivityWidth = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimStyle = TextStyle(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontSize: 13,
    );
    final normalStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontSize: 13,
    );

    switch (task.type) {
      case BackgroundTaskType.localBash:
        final displayText = task.kind == 'monitor'
            ? task.description
            : (task.command ?? task.description);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _truncate(displayText, maxActivityWidth),
                style: normalStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            ShellProgress(shell: task),
          ],
        );

      case BackgroundTaskType.remoteAgent:
        if (task.isRemoteReview) {
          return _RemoteSessionProgress(session: task);
        }
        final isRunning =
            task.status == TaskStatus.running ||
            task.status == TaskStatus.pending;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isRunning ? '\u25C7 ' : '\u25C6 ', // diamond open/filled
              style: dimStyle,
            ),
            Flexible(
              child: Text(
                _truncate(task.title ?? '', maxActivityWidth),
                style: normalStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(' \u00B7 ', style: dimStyle),
            _RemoteSessionProgress(session: task),
          ],
        );

      case BackgroundTaskType.localAgent:
        final doneLabel = task.status == TaskStatus.completed ? NeomageTranslationConstants.done.tr : null;
        final suffix = task.status == TaskStatus.completed && !task.notified
            ? ', unread'
            : null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _truncate(task.description, maxActivityWidth),
                style: normalStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            TaskStatusText(
              status: task.status,
              label: doneLabel,
              suffix: suffix,
            ),
          ],
        );

      case BackgroundTaskType.inProcessTeammate:
        final activity = describeTeammateActivity(task);
        final agentColor = task.identity?.color ?? theme.colorScheme.primary;
        final agentName = task.identity?.agentName ?? 'agent';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '@$agentName',
              style: TextStyle(color: agentColor, fontSize: 13),
            ),
            Text(': ', style: dimStyle),
            Flexible(
              child: Text(
                _truncate(activity, maxActivityWidth),
                style: dimStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

      case BackgroundTaskType.localWorkflow:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _truncate(task.summary ?? task.description, maxActivityWidth),
                style: normalStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            TaskStatusText(status: task.status),
          ],
        );

      case BackgroundTaskType.monitorMcp:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _truncate(task.description, maxActivityWidth),
                style: normalStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            TaskStatusText(status: task.status),
          ],
        );

      case BackgroundTaskType.dream:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _truncate(task.description, maxActivityWidth),
                style: normalStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            TaskStatusText(status: task.status),
          ],
        );
    }
  }
}

// ─── RemoteSessionProgress (small helper) ───

class _RemoteSessionProgress extends StatelessWidget {
  final BackgroundTaskState session;

  const _RemoteSessionProgress({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimStyle = TextStyle(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontSize: 12,
    );

    final statusLabel = switch (session.status) {
      TaskStatus.completed => NeomageTranslationConstants.done.tr,
      TaskStatus.failed => NeomageTranslationConstants.error.tr,
      TaskStatus.killed => NeomageTranslationConstants.stopped.tr,
      TaskStatus.running => 'running',
      TaskStatus.pending => 'pending',
    };

    return Text('($statusLabel)', style: dimStyle);
  }
}

// ─── BackgroundTasksController (SintController) ───

class BackgroundTasksController extends SintController {
  // Observable task map
  final tasks = <String, BackgroundTaskState>{}.obs;

  // View state
  final viewMode = 'list'.obs; // 'list' | 'detail'
  final detailTaskId = ''.obs;
  final selectedIndex = 0.obs;
  final showSpinnerTree = false.obs;
  final foregroundedTaskId = Rxn<String>();

  // Whether the dialog was opened directly to a task detail
  bool _skippedListOnMount = false;

  // Computed sorted list items
  List<TaskListItem> get allSelectableItems {
    final bgTasks = tasks.values.toList();
    final items = bgTasks.map(_toListItem).toList();

    // Sort: running first, then by start time descending
    items.sort((a, b) {
      if (a.status == TaskStatus.running && b.status != TaskStatus.running) {
        return -1;
      }
      if (a.status != TaskStatus.running && b.status == TaskStatus.running) {
        return 1;
      }
      final aTime = a.task?.startTime ?? DateTime(2000);
      final bTime = b.task?.startTime ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return items;
  }

  // Grouped tasks
  List<TaskListItem> get teammateTasks => showSpinnerTree.value
      ? <TaskListItem>[]
      : allSelectableItems
            .where((i) => i.type == BackgroundTaskType.inProcessTeammate)
            .toList();

  List<TaskListItem> get bashTasks => allSelectableItems
      .where((i) => i.type == BackgroundTaskType.localBash)
      .toList();

  List<TaskListItem> get remoteSessions => allSelectableItems
      .where((i) => i.type == BackgroundTaskType.remoteAgent)
      .toList();

  List<TaskListItem> get agentTasks => allSelectableItems
      .where(
        (i) =>
            i.type == BackgroundTaskType.localAgent &&
            i.id != foregroundedTaskId.value,
      )
      .toList();

  List<TaskListItem> get workflowTasks => allSelectableItems
      .where((i) => i.type == BackgroundTaskType.localWorkflow)
      .toList();

  List<TaskListItem> get mcpMonitors => allSelectableItems
      .where((i) => i.type == BackgroundTaskType.monitorMcp)
      .toList();

  List<TaskListItem> get dreamTasks => allSelectableItems
      .where((i) => i.type == BackgroundTaskType.dream)
      .toList();

  TaskListItem? get currentSelection {
    final items = allSelectableItems;
    if (selectedIndex.value >= 0 && selectedIndex.value < items.length) {
      return items[selectedIndex.value];
    }
    return null;
  }

  // Count helpers
  int get runningBashCount =>
      bashTasks.where((t) => t.status == TaskStatus.running).length;

  int get runningAgentCount =>
      remoteSessions
          .where(
            (t) =>
                t.status == TaskStatus.running ||
                t.status == TaskStatus.pending,
          )
          .length +
      agentTasks.where((t) => t.status == TaskStatus.running).length;

  int get runningTeammateCount =>
      teammateTasks.where((t) => t.status == TaskStatus.running).length;

  @override
  void onInit() {
    super.onInit();
    // Auto-navigate to detail if only one task
    final items = allSelectableItems;
    if (items.length == 1) {
      _skippedListOnMount = true;
      viewMode.value = 'detail';
      detailTaskId.value = items.first.id;
    }
  }

  /// Open with a specific task detail view.
  void openWithDetail(String taskId) {
    _skippedListOnMount = true;
    viewMode.value = 'detail';
    detailTaskId.value = taskId;
  }

  /// Navigate selection up.
  void selectPrevious() {
    if (selectedIndex.value > 0) {
      selectedIndex.value--;
    }
  }

  /// Navigate selection down.
  void selectNext() {
    final maxIdx = allSelectableItems.length - 1;
    if (selectedIndex.value < maxIdx) {
      selectedIndex.value++;
    }
  }

  /// Open detail view for current selection.
  void openCurrentDetail() {
    final current = currentSelection;
    if (current == null) return;
    if (current.isLeader) {
      // Leader => foreground main
      return;
    }
    viewMode.value = 'detail';
    detailTaskId.value = current.id;
  }

  /// Go back to list, or close if we skipped list on mount.
  void goBackToList(VoidCallback onDismiss) {
    if (_skippedListOnMount && allSelectableItems.length <= 1) {
      onDismiss();
    } else {
      _skippedListOnMount = false;
      viewMode.value = 'list';
    }
  }

  /// Kill a task by ID.
  Future<void> killTask(String taskId) async {
    final task = tasks[taskId];
    if (task == null) return;
    // Update task status to killed
    tasks[taskId] = BackgroundTaskState(
      id: task.id,
      type: task.type,
      status: TaskStatus.killed,
      description: task.description,
      command: task.command,
      title: task.title,
      summary: task.summary,
      startTime: task.startTime,
      identity: task.identity,
      progress: task.progress,
      kind: task.kind,
    );
    tasks.refresh();
  }

  TaskListItem _toListItem(BackgroundTaskState task) {
    switch (task.type) {
      case BackgroundTaskType.localBash:
        return TaskListItem(
          id: task.id,
          type: BackgroundTaskType.localBash,
          label: task.kind == 'monitor'
              ? task.description
              : (task.command ?? task.description),
          status: task.status,
          task: task,
        );
      case BackgroundTaskType.remoteAgent:
        return TaskListItem(
          id: task.id,
          type: BackgroundTaskType.remoteAgent,
          label: task.title ?? '',
          status: task.status,
          task: task,
        );
      case BackgroundTaskType.localAgent:
        return TaskListItem(
          id: task.id,
          type: BackgroundTaskType.localAgent,
          label: task.description,
          status: task.status,
          task: task,
        );
      case BackgroundTaskType.inProcessTeammate:
        return TaskListItem(
          id: task.id,
          type: BackgroundTaskType.inProcessTeammate,
          label: '@${task.identity?.agentName ?? 'agent'}',
          status: task.status,
          task: task,
        );
      case BackgroundTaskType.localWorkflow:
        return TaskListItem(
          id: task.id,
          type: BackgroundTaskType.localWorkflow,
          label: task.summary ?? task.description,
          status: task.status,
          task: task,
        );
      case BackgroundTaskType.monitorMcp:
        return TaskListItem(
          id: task.id,
          type: BackgroundTaskType.monitorMcp,
          label: task.description,
          status: task.status,
          task: task,
        );
      case BackgroundTaskType.dream:
        return TaskListItem(
          id: task.id,
          type: BackgroundTaskType.dream,
          label: task.description,
          status: task.status,
          task: task,
        );
    }
  }
}

// ─── BackgroundTasksDialog widget (mirrors BackgroundTasksDialog.tsx) ───

class BackgroundTasksDialog extends StatelessWidget {
  final VoidCallback onDismiss;
  final String? initialDetailTaskId;

  const BackgroundTasksDialog({
    super.key,
    required this.onDismiss,
    this.initialDetailTaskId,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<BackgroundTasksController>();

    if (initialDetailTaskId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.openWithDetail(initialDetailTaskId!);
      });
    }

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(event, controller),
      child: Obx(() {
        if (controller.viewMode.value == 'detail') {
          return _buildDetailView(context, controller);
        }
        return _buildListView(context, controller);
      }),
    );
  }

  void _handleKeyEvent(KeyEvent event, BackgroundTasksController controller) {
    if (event is! KeyDownEvent) return;

    if (controller.viewMode.value == 'list') {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          controller.selectPrevious();
        case LogicalKeyboardKey.arrowDown:
          controller.selectNext();
        case LogicalKeyboardKey.enter:
          controller.openCurrentDetail();
        case LogicalKeyboardKey.escape:
        case LogicalKeyboardKey.arrowLeft:
          onDismiss();
        case LogicalKeyboardKey.keyX:
          _handleKillCurrent(controller);
        case LogicalKeyboardKey.keyF:
          _handleForegroundCurrent(controller);
        default:
          break;
      }
    } else {
      // Detail mode
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
        case LogicalKeyboardKey.arrowLeft:
          controller.goBackToList(onDismiss);
        default:
          break;
      }
    }
  }

  void _handleKillCurrent(BackgroundTasksController controller) {
    final current = controller.currentSelection;
    if (current == null || current.status != TaskStatus.running) return;
    controller.killTask(current.id);
  }

  void _handleForegroundCurrent(BackgroundTasksController controller) {
    final current = controller.currentSelection;
    if (current == null) return;
    if (current.type == BackgroundTaskType.inProcessTeammate &&
        current.status == TaskStatus.running) {
      // Foreground teammate
      onDismiss();
    }
  }

  Widget _buildListView(
    BuildContext context,
    BackgroundTasksController controller,
  ) {
    final theme = Theme.of(context);
    final items = controller.allSelectableItems;
    final teammates = controller.teammateTasks;
    final bash = controller.bashTasks;
    final monitors = controller.mcpMonitors;
    final remote = controller.remoteSessions;
    final agents = controller.agentTasks;
    final workflows = controller.workflowTasks;
    final dreams = controller.dreamTasks;

    // Subtitle
    final subtitleParts = <String>[];
    if (controller.runningTeammateCount > 0) {
      subtitleParts.add(
        '${controller.runningTeammateCount} ${controller.runningTeammateCount != 1 ? 'agents' : 'agent'}',
      );
    }
    if (controller.runningBashCount > 0) {
      subtitleParts.add(
        '${controller.runningBashCount} ${controller.runningBashCount != 1 ? 'active shells' : 'active shell'}',
      );
    }
    if (controller.runningAgentCount > 0) {
      subtitleParts.add(
        '${controller.runningAgentCount} ${controller.runningAgentCount != 1 ? 'active agents' : 'active agent'}',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  'Background tasks',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    subtitleParts.join(' \u00B7 '),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Task list
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No tasks currently running',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Teammates section
                    if (teammates.isNotEmpty)
                      _TaskSection(
                        title: 'Agents',
                        count: teammates.where((i) => !i.isLeader).length,
                        showTitle:
                            bash.isNotEmpty ||
                            remote.isNotEmpty ||
                            agents.isNotEmpty,
                        items: teammates,
                        selectedId: controller.currentSelection?.id,
                      ),

                    // Bash section
                    if (bash.isNotEmpty)
                      _TaskSection(
                        title: 'Shells',
                        count: bash.length,
                        showTitle:
                            teammates.isNotEmpty ||
                            remote.isNotEmpty ||
                            agents.isNotEmpty,
                        items: bash,
                        selectedId: controller.currentSelection?.id,
                        topPadding: teammates.isNotEmpty,
                      ),

                    // Monitors section
                    if (monitors.isNotEmpty)
                      _TaskSection(
                        title: 'Monitors',
                        count: monitors.length,
                        showTitle: true,
                        items: monitors,
                        selectedId: controller.currentSelection?.id,
                        topPadding: teammates.isNotEmpty || bash.isNotEmpty,
                      ),

                    // Remote agents section
                    if (remote.isNotEmpty)
                      _TaskSection(
                        title: 'Remote agents',
                        count: remote.length,
                        showTitle: true,
                        items: remote,
                        selectedId: controller.currentSelection?.id,
                        topPadding:
                            teammates.isNotEmpty ||
                            bash.isNotEmpty ||
                            monitors.isNotEmpty,
                      ),

                    // Local agents section
                    if (agents.isNotEmpty)
                      _TaskSection(
                        title: 'Local agents',
                        count: agents.length,
                        showTitle: true,
                        items: agents,
                        selectedId: controller.currentSelection?.id,
                        topPadding:
                            teammates.isNotEmpty ||
                            bash.isNotEmpty ||
                            monitors.isNotEmpty ||
                            remote.isNotEmpty,
                      ),

                    // Workflows section
                    if (workflows.isNotEmpty)
                      _TaskSection(
                        title: 'Workflows',
                        count: workflows.length,
                        showTitle: true,
                        items: workflows,
                        selectedId: controller.currentSelection?.id,
                        topPadding:
                            teammates.isNotEmpty ||
                            bash.isNotEmpty ||
                            monitors.isNotEmpty ||
                            remote.isNotEmpty ||
                            agents.isNotEmpty,
                      ),

                    // Dreams section
                    if (dreams.isNotEmpty)
                      _TaskSection(
                        title: 'Dreams',
                        count: dreams.length,
                        showTitle: false,
                        items: dreams,
                        selectedId: controller.currentSelection?.id,
                        topPadding:
                            teammates.isNotEmpty ||
                            bash.isNotEmpty ||
                            monitors.isNotEmpty ||
                            remote.isNotEmpty ||
                            agents.isNotEmpty ||
                            workflows.isNotEmpty,
                      ),
                  ],
                ),
              ),
            ),

          const Divider(height: 1),

          // Action bar
          _ActionBar(controller: controller),
        ],
      ),
    );
  }

  Widget _buildDetailView(
    BuildContext context,
    BackgroundTasksController controller,
  ) {
    final taskId = controller.detailTaskId.value;
    final task = controller.tasks[taskId];

    if (task == null) {
      return Center(child: Text(NeomageTranslationConstants.taskNotFound.tr));
    }

    return _TaskDetailView(
      task: task,
      onBack: () => controller.goBackToList(onDismiss),
      onKill: task.isRunning ? () => controller.killTask(task.id) : null,
    );
  }
}

// ─── TaskSection (grouped section in the list) ───

class _TaskSection extends StatelessWidget {
  final String title;
  final int count;
  final bool showTitle;
  final List<TaskListItem> items;
  final String? selectedId;
  final bool topPadding;

  const _TaskSection({
    required this.title,
    required this.count,
    required this.showTitle,
    required this.items,
    this.selectedId,
    this.topPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topPadding) const SizedBox(height: 8),
        if (showTitle)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              '  $title ($count)',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ...items.map(
          (item) =>
              _TaskListTile(item: item, isSelected: item.id == selectedId),
        ),
      ],
    );
  }
}

// ─── TaskListTile (single item in the list) ───

class _TaskListTile extends StatelessWidget {
  final TaskListItem item;
  final bool isSelected;

  const _TaskListTile({required this.item, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text(
              isSelected ? '\u25B6 ' : '  ',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: item.isLeader
                ? Text(
                    item.label,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  )
                : BackgroundTaskItem(task: item.task!, maxActivityWidth: 50),
          ),
        ],
      ),
    );
  }
}

// ─── ActionBar (bottom keyboard hint bar) ───

class _ActionBar extends StatelessWidget {
  final BackgroundTasksController controller;

  const _ActionBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = TextStyle(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontSize: 11,
    );
    final keyStyle = TextStyle(
      color: theme.colorScheme.primary,
      fontSize: 11,
      fontWeight: FontWeight.bold,
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 12,
        children: [
          _KeyHint(
            keyStyle: keyStyle,
            hintStyle: hintStyle,
            key_: '\u2191/\u2193',
            action: 'select',
          ),
          _KeyHint(
            keyStyle: keyStyle,
            hintStyle: hintStyle,
            key_: 'Enter',
            action: 'view',
          ),
          if (controller.currentSelection?.type ==
                  BackgroundTaskType.inProcessTeammate &&
              controller.currentSelection?.status == TaskStatus.running)
            _KeyHint(
              keyStyle: keyStyle,
              hintStyle: hintStyle,
              key_: 'f',
              action: 'foreground',
            ),
          if (controller.currentSelection != null &&
              controller.currentSelection!.status == TaskStatus.running)
            _KeyHint(
              keyStyle: keyStyle,
              hintStyle: hintStyle,
              key_: 'x',
              action: 'stop',
            ),
          _KeyHint(
            keyStyle: keyStyle,
            hintStyle: hintStyle,
            key_: '\u2190/Esc',
            action: 'close',
          ),
        ],
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  final TextStyle keyStyle;
  final TextStyle hintStyle;
  final String key_;
  final String action;

  const _KeyHint({
    required this.keyStyle,
    required this.hintStyle,
    required this.key_,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: key_, style: keyStyle),
          TextSpan(text: ' $action', style: hintStyle),
        ],
      ),
    );
  }
}

// ─── TaskDetailView (detail panel for a single task) ───

class _TaskDetailView extends StatelessWidget {
  final BackgroundTaskState task;
  final VoidCallback onBack;
  final VoidCallback? onKill;

  const _TaskDetailView({
    required this.task,
    required this.onBack,
    this.onKill,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusColor = getTaskStatusColor(
      context,
      task.status,
      isIdle: task.isIdle,
      awaitingApproval: task.awaitingApproval,
      hasError: task.hasError,
      shutdownRequested: task.shutdownRequested,
    );

    final statusIcon = getTaskStatusIcon(
      task.status,
      isIdle: task.isIdle,
      awaitingApproval: task.awaitingApproval,
      hasError: task.hasError,
      shutdownRequested: task.shutdownRequested,
    );

    final typeLabel = switch (task.type) {
      BackgroundTaskType.localBash => 'Shell Task',
      BackgroundTaskType.remoteAgent => 'Remote Agent',
      BackgroundTaskType.localAgent => 'Local Agent',
      BackgroundTaskType.inProcessTeammate => 'Teammate',
      BackgroundTaskType.localWorkflow => 'Workflow',
      BackgroundTaskType.monitorMcp => 'MCP Monitor',
      BackgroundTaskType.dream => 'Dream',
    };

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    typeLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onKill != null)
                  TextButton.icon(
                    icon: const Icon(Icons.stop, size: 16),
                    label: Text(NeomageTranslationConstants.stop.tr),
                    onPressed: onKill,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Details
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status row
                  _DetailRow(
                    label: NeomageTranslationConstants.status.tr,
                    value: task.status.name,
                    valueColor: statusColor,
                  ),

                  const SizedBox(height: 8),

                  // Description
                  _DetailRow(label: NeomageTranslationConstants.description.tr, value: task.description),

                  // Command (for shell tasks)
                  if (task.command != null) ...[
                    const SizedBox(height: 8),
                    _DetailRow(label: NeomageTranslationConstants.command.tr, value: task.command!),
                  ],

                  // Title (for remote agents)
                  if (task.title != null) ...[
                    const SizedBox(height: 8),
                    _DetailRow(label: NeomageTranslationConstants.title.tr, value: task.title!),
                  ],

                  // Agent name (for teammates)
                  if (task.identity != null) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      label: NeomageTranslationConstants.agent.tr,
                      value: '@${task.identity!.agentName}',
                      valueColor: task.identity!.color,
                    ),
                  ],

                  // Activity (for teammates)
                  if (task.type == BackgroundTaskType.inProcessTeammate) ...[
                    const SizedBox(height: 8),
                    _DetailRow(
                      label: NeomageTranslationConstants.activity.tr,
                      value: describeTeammateActivity(task),
                    ),
                  ],

                  // Start time
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: NeomageTranslationConstants.started.tr,
                    value: _formatTime(task.startTime),
                  ),

                  // Duration
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: NeomageTranslationConstants.duration.tr,
                    value: _formatDuration(
                      DateTime.now().difference(task.startTime),
                    ),
                  ),

                  // State flags
                  if (task.isIdle ||
                      task.awaitingApproval ||
                      task.shutdownRequested ||
                      task.hasError) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (task.isIdle)
                          _StateChip(label: NeomageTranslationConstants.idle.tr, color: Colors.grey),
                        if (task.awaitingApproval)
                          _StateChip(
                            label: NeomageTranslationConstants.awaitingApproval.tr,
                            color: Colors.orange,
                          ),
                        if (task.shutdownRequested)
                          _StateChip(
                            label: NeomageTranslationConstants.shutdownRequested.tr,
                            color: Colors.orange,
                          ),
                        if (task.hasError)
                          _StateChip(
                            label: NeomageTranslationConstants.error.tr,
                            color: theme.colorScheme.error,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? theme.colorScheme.onSurface,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _StateChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StateChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}

// ─── BackgroundTaskStatusBar widget (mirrors BackgroundTaskStatus.tsx) ───
// This is the footer pills bar showing teammate status or task count.

class BackgroundTaskStatusBar extends StatelessWidget {
  final bool tasksSelected;
  final bool isViewingTeammate;
  final int teammateFooterIndex;
  final bool isLeaderIdle;
  final VoidCallback? onOpenDialog;

  const BackgroundTaskStatusBar({
    super.key,
    this.tasksSelected = false,
    this.isViewingTeammate = false,
    this.teammateFooterIndex = 0,
    this.isLeaderIdle = false,
    this.onOpenDialog,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<BackgroundTasksController>();

    return Obx(() {
      final tasks = controller.tasks;
      final runningTasks = tasks.values.where((t) => !t.isTerminal).toList();
      final showSpinnerTree = controller.showSpinnerTree.value;

      // Check if all tasks are teammates (show pills instead)
      final allTeammates =
          !showSpinnerTree &&
          runningTasks.isNotEmpty &&
          runningTasks.every(
            (t) => t.type == BackgroundTaskType.inProcessTeammate,
          );

      if (allTeammates || (!showSpinnerTree && isViewingTeammate)) {
        return _buildTeammatePills(context, controller, runningTasks);
      }

      if (shouldHideTasksFooter(tasks, showSpinnerTree)) {
        return const SizedBox.shrink();
      }

      if (runningTasks.isEmpty) {
        return const SizedBox.shrink();
      }

      // Simple count display
      return _buildCountDisplay(context, runningTasks);
    });
  }

  Widget _buildTeammatePills(
    BuildContext context,
    BackgroundTasksController controller,
    List<BackgroundTaskState> tasks,
  ) {
    final theme = Theme.of(context);
    final teammates =
        tasks
            .where((t) => t.type == BackgroundTaskType.inProcessTeammate)
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main pill
          _AgentPill(
            name: 'main',
            isSelected: tasksSelected && teammateFooterIndex == 0,
            isViewed: !isViewingTeammate,
            isIdle: isLeaderIdle,
          ),
          ...teammates.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final t = entry.value;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _AgentPill(
                name: t.identity?.agentName ?? 'agent',
                color: t.identity?.color,
                isSelected: tasksSelected && teammateFooterIndex == idx,
                isViewed: false,
                isIdle: t.isIdle,
              ),
            );
          }),
          const SizedBox(width: 8),
          Text(
            ' \u00B7 Shift+\u2193 expand',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountDisplay(
    BuildContext context,
    List<BackgroundTaskState> runningTasks,
  ) {
    final theme = Theme.of(context);
    final count = runningTasks.length;

    return GestureDetector(
      onTap: onOpenDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              '$count ${count == 1 ? 'task' : 'tasks'}',
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AgentPill (teammate pill in the status bar) ───

class _AgentPill extends StatelessWidget {
  final String name;
  final Color? color;
  final bool isSelected;
  final bool isViewed;
  final bool isIdle;

  const _AgentPill({
    required this.name,
    this.color,
    required this.isSelected,
    required this.isViewed,
    required this.isIdle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pillColor = color ?? theme.colorScheme.primary;
    final bgColor = isViewed
        ? pillColor.withValues(alpha: 0.2)
        : isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : Colors.transparent;
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : pillColor.withValues(alpha: 0.3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
      ),
      child: Text(
        name,
        style: TextStyle(
          color: isIdle
              ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
              : pillColor,
          fontSize: 11,
          fontWeight: isViewed ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
