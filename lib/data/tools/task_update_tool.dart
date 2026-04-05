// TaskUpdateTool — port of neomage/src/tools/TaskUpdateTool/.
// Update task status, subject, description, ownership, dependencies,
// and metadata in the task list, with hook execution, teammate mailbox
// notifications, and verification nudges.

import 'dart:async';
import 'dart:convert';

import 'tool.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const String taskUpdateToolName = 'TaskUpdate';

const String taskUpdateToolDescription = 'Update a task in the task list';

/// Agent type identifier for the verification agent.
const String verificationAgentType = 'verification';

// ─── Task Status ─────────────────────────────────────────────────────────────

/// Valid task statuses.
enum TaskStatus {
  pending,
  inProgress,
  completed;

  /// Parse from a JSON string.
  static TaskStatus? fromString(String s) {
    switch (s) {
      case 'pending':
        return TaskStatus.pending;
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'completed':
        return TaskStatus.completed;
      default:
        return null;
    }
  }

  /// Convert to JSON string.
  String toJsonString() {
    switch (this) {
      case TaskStatus.pending:
        return 'pending';
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.completed:
        return 'completed';
    }
  }

  @override
  String toString() => toJsonString();
}

/// Extended status that includes 'deleted' as a special action.
class TaskUpdateStatus {
  final TaskStatus? status;
  final bool isDeleted;

  const TaskUpdateStatus.status(TaskStatus this.status) : isDeleted = false;
  const TaskUpdateStatus.deleted() : status = null, isDeleted = true;

  /// Parse from string, supporting 'deleted' in addition to regular statuses.
  static TaskUpdateStatus? fromString(String s) {
    if (s == 'deleted') return const TaskUpdateStatus.deleted();
    final status = TaskStatus.fromString(s);
    if (status == null) return null;
    return TaskUpdateStatus.status(status);
  }
}

// ─── Task Model ──────────────────────────────────────────────────────────────

/// A task in the task list.
class Task {
  final String id;
  String subject;
  String? description;
  String? activeForm;
  TaskStatus status;
  String? owner;
  List<String> blocks;
  List<String> blockedBy;
  Map<String, dynamic>? metadata;
  DateTime createdAt;
  DateTime updatedAt;

  Task({
    required this.id,
    required this.subject,
    this.description,
    this.activeForm,
    this.status = TaskStatus.pending,
    this.owner,
    this.blocks = const [],
    this.blockedBy = const [],
    this.metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    subject: json['subject'] as String,
    description: json['description'] as String?,
    activeForm: json['activeForm'] as String?,
    status:
        TaskStatus.fromString(json['status'] as String? ?? 'pending') ??
        TaskStatus.pending,
    owner: json['owner'] as String?,
    blocks:
        (json['blocks'] as List<dynamic>?)?.map((e) => e as String).toList() ??
        const [],
    blockedBy:
        (json['blockedBy'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        const [],
    metadata: json['metadata'] as Map<String, dynamic>?,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    updatedAt: json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'subject': subject,
    if (description != null) 'description': description,
    if (activeForm != null) 'activeForm': activeForm,
    'status': status.toJsonString(),
    if (owner != null) 'owner': owner,
    'blocks': blocks,
    'blockedBy': blockedBy,
    if (metadata != null) 'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

// ─── Task Store Interface ────────────────────────────────────────────────────

/// Abstract task storage interface.
abstract class TaskStore {
  /// Get the current task list ID.
  String getTaskListId();

  /// Get a task by ID.
  Future<Task?> getTask(String taskListId, String taskId);

  /// Update a task.
  Future<void> updateTask(
    String taskListId,
    String taskId,
    Map<String, dynamic> updates,
  );

  /// Delete a task.
  Future<bool> deleteTask(String taskListId, String taskId);

  /// Add a blocking relationship: taskId blocks blockedTaskId.
  Future<void> blockTask(
    String taskListId,
    String taskId,
    String blockedTaskId,
  );

  /// List all tasks.
  Future<List<Task>> listTasks(String taskListId);
}

/// In-memory task store for default/testing usage.
class InMemoryTaskStore implements TaskStore {
  final Map<String, Map<String, Task>> _lists = {};

  @override
  String getTaskListId() => 'default';

  @override
  Future<Task?> getTask(String taskListId, String taskId) async {
    return _lists[taskListId]?[taskId];
  }

  @override
  Future<void> updateTask(
    String taskListId,
    String taskId,
    Map<String, dynamic> updates,
  ) async {
    final task = _lists[taskListId]?[taskId];
    if (task == null) return;

    if (updates.containsKey('subject')) {
      task.subject = updates['subject'] as String;
    }
    if (updates.containsKey('description')) {
      task.description = updates['description'] as String?;
    }
    if (updates.containsKey('activeForm')) {
      task.activeForm = updates['activeForm'] as String?;
    }
    if (updates.containsKey('status')) {
      task.status = updates['status'] as TaskStatus;
    }
    if (updates.containsKey('owner')) {
      task.owner = updates['owner'] as String?;
    }
    if (updates.containsKey('metadata')) {
      task.metadata = updates['metadata'] as Map<String, dynamic>?;
    }
    task.updatedAt = DateTime.now();
  }

  @override
  Future<bool> deleteTask(String taskListId, String taskId) async {
    return _lists[taskListId]?.remove(taskId) != null;
  }

  @override
  Future<void> blockTask(
    String taskListId,
    String taskId,
    String blockedTaskId,
  ) async {
    final blocker = _lists[taskListId]?[taskId];
    final blocked = _lists[taskListId]?[blockedTaskId];
    if (blocker != null && !blocker.blocks.contains(blockedTaskId)) {
      blocker.blocks = [...blocker.blocks, blockedTaskId];
    }
    if (blocked != null && !blocked.blockedBy.contains(taskId)) {
      blocked.blockedBy = [...blocked.blockedBy, taskId];
    }
  }

  @override
  Future<List<Task>> listTasks(String taskListId) async {
    return _lists[taskListId]?.values.toList() ?? [];
  }

  /// Add a task (for testing).
  void addTask(String taskListId, Task task) {
    _lists.putIfAbsent(taskListId, () => {});
    _lists[taskListId]![task.id] = task;
  }
}

// ─── Teammate Mailbox ────────────────────────────────────────────────────────

/// A mailbox message sent to a teammate.
class MailboxMessage {
  final String from;
  final String text;
  final String timestamp;
  final String? color;

  const MailboxMessage({
    required this.from,
    required this.text,
    required this.timestamp,
    this.color,
  });

  Map<String, dynamic> toJson() => {
    'from': from,
    'text': text,
    'timestamp': timestamp,
    if (color != null) 'color': color,
  };
}

/// Callback type for writing to teammate mailbox.
typedef WriteToMailboxFn =
    Future<void> Function(
      String recipientName,
      MailboxMessage message,
      String taskListId,
    );

// ─── Task Completed Hook ─────────────────────────────────────────────────────

/// Result from a task-completed hook execution.
class TaskCompletedHookResult {
  final String? blockingError;

  const TaskCompletedHookResult({this.blockingError});
}

/// Callback type for executing task-completed hooks.
typedef ExecuteTaskCompletedHooksFn =
    Stream<TaskCompletedHookResult> Function({
      required String taskId,
      required String subject,
      String? description,
      String? agentName,
      String? teamName,
    });

// ─── TaskUpdateTool Input / Output ───────────────────────────────────────────

/// Input for the TaskUpdateTool.
class TaskUpdateToolInput {
  final String taskId;
  final String? subject;
  final String? description;
  final String? activeForm;
  final String? status; // TaskStatus string or 'deleted'
  final List<String>? addBlocks;
  final List<String>? addBlockedBy;
  final String? owner;
  final Map<String, dynamic>? metadata;

  const TaskUpdateToolInput({
    required this.taskId,
    this.subject,
    this.description,
    this.activeForm,
    this.status,
    this.addBlocks,
    this.addBlockedBy,
    this.owner,
    this.metadata,
  });

  factory TaskUpdateToolInput.fromJson(Map<String, dynamic> json) =>
      TaskUpdateToolInput(
        taskId: json['taskId'] as String,
        subject: json['subject'] as String?,
        description: json['description'] as String?,
        activeForm: json['activeForm'] as String?,
        status: json['status'] as String?,
        addBlocks: (json['addBlocks'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        addBlockedBy: (json['addBlockedBy'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        owner: json['owner'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

/// Output for the TaskUpdateTool.
class TaskUpdateToolOutput {
  final bool success;
  final String taskId;
  final List<String> updatedFields;
  final String? error;
  final ({String from, String to})? statusChange;
  final bool verificationNudgeNeeded;

  const TaskUpdateToolOutput({
    required this.success,
    required this.taskId,
    required this.updatedFields,
    this.error,
    this.statusChange,
    this.verificationNudgeNeeded = false,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'taskId': taskId,
    'updatedFields': updatedFields,
    if (error != null) 'error': error,
    if (statusChange != null)
      'statusChange': {'from': statusChange!.from, 'to': statusChange!.to},
    if (verificationNudgeNeeded) 'verificationNudgeNeeded': true,
  };
}

// ─── TaskUpdateTool Implementation ───────────────────────────────────────────

/// The TaskUpdateTool — update tasks in the task list.
class TaskUpdateTool extends Tool {
  final TaskStore _taskStore;
  final bool _isEnabled;
  final bool _agentSwarmsEnabled;
  final String? _agentName;
  final String? _agentId;
  final String? _agentColor;
  final String? _teamName;
  final WriteToMailboxFn? _writeToMailbox;
  final ExecuteTaskCompletedHooksFn? _executeHooks;
  final bool _verificationEnabled;

  /// Callback for expanding the task view in the UI.
  final void Function()? onExpandTaskView;

  TaskUpdateTool({
    TaskStore? taskStore,
    bool isEnabled = true,
    bool agentSwarmsEnabled = false,
    String? agentName,
    String? agentId,
    String? agentColor,
    String? teamName,
    WriteToMailboxFn? writeToMailbox,
    ExecuteTaskCompletedHooksFn? executeHooks,
    bool verificationEnabled = false,
    this.onExpandTaskView,
  }) : _taskStore = taskStore ?? InMemoryTaskStore(),
       _isEnabled = isEnabled,
       _agentSwarmsEnabled = agentSwarmsEnabled,
       _agentName = agentName,
       _agentId = agentId,
       _agentColor = agentColor,
       _teamName = teamName,
       _writeToMailbox = writeToMailbox,
       _executeHooks = executeHooks,
       _verificationEnabled = verificationEnabled;

  @override
  String get name => taskUpdateToolName;

  @override
  String get description => taskUpdateToolDescription;

  @override
  String get userFacingName => 'TaskUpdate';

  @override
  bool get shouldDefer => true;

  @override
  bool get isEnabled => _isEnabled;

  @override
  bool get isConcurrencySafe => true;

  @override
  int? get maxResultSizeChars => 100000;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'taskId': {
        'type': 'string',
        'description': 'The ID of the task to update',
      },
      'subject': {'type': 'string', 'description': 'New subject for the task'},
      'description': {
        'type': 'string',
        'description': 'New description for the task',
      },
      'activeForm': {
        'type': 'string',
        'description':
            'Present continuous form shown in spinner when in_progress '
            '(e.g., "Running tests")',
      },
      'status': {
        'type': 'string',
        'description': 'New status for the task',
        'enum': ['pending', 'in_progress', 'completed', 'deleted'],
      },
      'addBlocks': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Task IDs that this task blocks',
      },
      'addBlockedBy': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Task IDs that block this task',
      },
      'owner': {'type': 'string', 'description': 'New owner for the task'},
      'metadata': {
        'type': 'object',
        'description':
            'Metadata keys to merge into the task. Set a key to null '
            'to delete it.',
      },
    },
    'required': ['taskId'],
    'additionalProperties': false,
  };

  @override
  String get prompt => _taskUpdatePrompt;

  @override
  String toAutoClassifierInput(Map<String, dynamic> input) {
    final parts = <String>[input['taskId'] as String? ?? ''];
    final status = input['status'] as String?;
    if (status != null) parts.add(status);
    final subject = input['subject'] as String?;
    if (subject != null) parts.add(subject);
    return parts.join(' ');
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = TaskUpdateToolInput.fromJson(input);
    final taskListId = _taskStore.getTaskListId();

    // Auto-expand task list.
    onExpandTaskView?.call();

    // Check if task exists.
    final existingTask = await _taskStore.getTask(taskListId, parsed.taskId);
    if (existingTask == null) {
      return _formatResult(
        TaskUpdateToolOutput(
          success: false,
          taskId: parsed.taskId,
          updatedFields: const [],
          error: 'Task not found',
        ),
      );
    }

    final updatedFields = <String>[];
    final updates = <String, dynamic>{};

    // Update basic fields if provided and different.
    if (parsed.subject != null && parsed.subject != existingTask.subject) {
      updates['subject'] = parsed.subject;
      updatedFields.add('subject');
    }
    if (parsed.description != null &&
        parsed.description != existingTask.description) {
      updates['description'] = parsed.description;
      updatedFields.add('description');
    }
    if (parsed.activeForm != null &&
        parsed.activeForm != existingTask.activeForm) {
      updates['activeForm'] = parsed.activeForm;
      updatedFields.add('activeForm');
    }
    if (parsed.owner != null && parsed.owner != existingTask.owner) {
      updates['owner'] = parsed.owner;
      updatedFields.add('owner');
    }

    // Auto-set owner when a teammate marks a task as in_progress.
    if (_agentSwarmsEnabled &&
        parsed.status == 'in_progress' &&
        parsed.owner == null &&
        existingTask.owner == null &&
        _agentName != null) {
      updates['owner'] = _agentName;
      updatedFields.add('owner');
    }

    // Merge metadata.
    if (parsed.metadata != null) {
      final merged = Map<String, dynamic>.from(existingTask.metadata ?? {});
      for (final entry in parsed.metadata!.entries) {
        if (entry.value == null) {
          merged.remove(entry.key);
        } else {
          merged[entry.key] = entry.value;
        }
      }
      updates['metadata'] = merged;
      updatedFields.add('metadata');
    }

    // Handle status changes.
    if (parsed.status != null) {
      final updateStatus = TaskUpdateStatus.fromString(parsed.status!);

      // Handle deletion.
      if (updateStatus != null && updateStatus.isDeleted) {
        final deleted = await _taskStore.deleteTask(taskListId, parsed.taskId);
        return _formatResult(
          TaskUpdateToolOutput(
            success: deleted,
            taskId: parsed.taskId,
            updatedFields: deleted ? const ['deleted'] : const [],
            error: deleted ? null : 'Failed to delete task',
            statusChange: deleted
                ? (from: existingTask.status.toJsonString(), to: 'deleted')
                : null,
          ),
        );
      }

      // Regular status update.
      if (updateStatus?.status != null &&
          updateStatus!.status != existingTask.status) {
        // Run TaskCompleted hooks.
        if (updateStatus.status == TaskStatus.completed &&
            _executeHooks != null) {
          final blockingErrors = <String>[];
          await for (final result in _executeHooks(
            taskId: parsed.taskId,
            subject: existingTask.subject,
            description: existingTask.description,
            agentName: _agentName,
            teamName: _teamName,
          )) {
            if (result.blockingError != null) {
              blockingErrors.add(result.blockingError!);
            }
          }

          if (blockingErrors.isNotEmpty) {
            return _formatResult(
              TaskUpdateToolOutput(
                success: false,
                taskId: parsed.taskId,
                updatedFields: const [],
                error: blockingErrors.join('\n'),
              ),
            );
          }
        }

        updates['status'] = updateStatus.status;
        updatedFields.add('status');
      }
    }

    // Apply updates.
    if (updates.isNotEmpty) {
      await _taskStore.updateTask(taskListId, parsed.taskId, updates);
    }

    // Notify new owner via mailbox.
    if (updates.containsKey('owner') &&
        _agentSwarmsEnabled &&
        _writeToMailbox != null) {
      final senderName = _agentName ?? 'team-lead';
      final assignmentMessage = jsonEncode({
        'type': 'task_assignment',
        'taskId': parsed.taskId,
        'subject': existingTask.subject,
        'description': existingTask.description,
        'assignedBy': senderName,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _writeToMailbox(
        updates['owner'] as String,
        MailboxMessage(
          from: senderName,
          text: assignmentMessage,
          timestamp: DateTime.now().toIso8601String(),
          color: _agentColor,
        ),
        taskListId,
      );
    }

    // Add blocks.
    if (parsed.addBlocks != null && parsed.addBlocks!.isNotEmpty) {
      final newBlocks = parsed.addBlocks!
          .where((id) => !existingTask.blocks.contains(id))
          .toList();
      for (final blockId in newBlocks) {
        await _taskStore.blockTask(taskListId, parsed.taskId, blockId);
      }
      if (newBlocks.isNotEmpty) updatedFields.add('blocks');
    }

    // Add blockedBy (reverse relationship).
    if (parsed.addBlockedBy != null && parsed.addBlockedBy!.isNotEmpty) {
      final newBlockedBy = parsed.addBlockedBy!
          .where((id) => !existingTask.blockedBy.contains(id))
          .toList();
      for (final blockerId in newBlockedBy) {
        await _taskStore.blockTask(taskListId, blockerId, parsed.taskId);
      }
      if (newBlockedBy.isNotEmpty) updatedFields.add('blockedBy');
    }

    // Verification nudge check.
    var verificationNudgeNeeded = false;
    if (_verificationEnabled &&
        _agentId == null &&
        updates['status'] is TaskStatus &&
        (updates['status'] as TaskStatus) == TaskStatus.completed) {
      final allTasks = await _taskStore.listTasks(taskListId);
      final allDone = allTasks.every((t) => t.status == TaskStatus.completed);
      if (allDone &&
          allTasks.length >= 3 &&
          !allTasks.any(
            (t) => RegExp(r'verif', caseSensitive: false).hasMatch(t.subject),
          )) {
        verificationNudgeNeeded = true;
      }
    }

    return _formatResult(
      TaskUpdateToolOutput(
        success: true,
        taskId: parsed.taskId,
        updatedFields: updatedFields,
        statusChange: updates.containsKey('status')
            ? (
                from: existingTask.status.toJsonString(),
                to: (updates['status'] as TaskStatus).toJsonString(),
              )
            : null,
        verificationNudgeNeeded: verificationNudgeNeeded,
      ),
    );
  }

  /// Format the output into a ToolResult.
  ToolResult _formatResult(TaskUpdateToolOutput output) {
    if (!output.success) {
      return ToolResult(
        content: output.error ?? 'Task #${output.taskId} not found',
        metadata: output.toJson(),
      );
    }

    var content =
        'Updated task #${output.taskId} ${output.updatedFields.join(", ")}';

    // Reminder for teammates.
    if (output.statusChange?.to == 'completed' &&
        _agentId != null &&
        _agentSwarmsEnabled) {
      content +=
          '\n\nTask completed. Call TaskList now to find your next available '
          'task or see if your work unblocked others.';
    }

    // Verification nudge.
    if (output.verificationNudgeNeeded) {
      content +=
          '\n\nNOTE: You just closed out 3+ tasks and none of them was a '
          'verification step. Before writing your final summary, spawn the '
          'verification agent (subagent_type="$verificationAgentType"). You '
          'cannot self-assign PARTIAL by listing caveats in your summary '
          '-- only the verifier issues a verdict.';
    }

    return ToolResult.success(content, metadata: output.toJson());
  }

  static const String _taskUpdatePrompt =
      '''Use this tool to update a task in the task list.

## When to Use This Tool

**Mark tasks as resolved:**
- When you have completed the work described in a task
- When a task is no longer needed or has been superseded
- IMPORTANT: Always mark your assigned tasks as resolved when you finish them
- After resolving, call TaskList to find your next task

- ONLY mark a task as completed when you have FULLY accomplished it
- If you encounter errors, blockers, or cannot finish, keep the task as in_progress
- When blocked, create a new task describing what needs to be resolved
- Never mark a task as completed if:
  - Tests are failing
  - Implementation is partial
  - You encountered unresolved errors
  - You couldn't find necessary files or dependencies

**Delete tasks:**
- When a task is no longer relevant or was created in error
- Setting status to `deleted` permanently removes the task

**Update task details:**
- When requirements change or become clearer
- When establishing dependencies between tasks

## Fields You Can Update

- **status**: The task status (see Status Workflow below)
- **subject**: Change the task title (imperative form, e.g., "Run tests")
- **description**: Change the task description
- **activeForm**: Present continuous form shown in spinner when in_progress (e.g., "Running tests")
- **owner**: Change the task owner (agent name)
- **metadata**: Merge metadata keys into the task (set a key to null to delete it)
- **addBlocks**: Mark tasks that cannot start until this one completes
- **addBlockedBy**: Mark tasks that must complete before this one can start

## Status Workflow

Status progresses: `pending` -> `in_progress` -> `completed`

Use `deleted` to permanently remove a task.

## Staleness

Make sure to read a task's latest state using `TaskGet` before updating it.

## Examples

Mark task as in progress when starting work:
```json
{"taskId": "1", "status": "in_progress"}
```

Mark task as completed after finishing work:
```json
{"taskId": "1", "status": "completed"}
```

Delete a task:
```json
{"taskId": "1", "status": "deleted"}
```

Claim a task by setting owner:
```json
{"taskId": "1", "owner": "my-name"}
```

Set up task dependencies:
```json
{"taskId": "2", "addBlockedBy": ["1"]}
```
''';
}
