// TaskOutput tool — port of neom_claw/src/tools/TaskOutputTool.
// Retrieves output from background tasks (agents, bash commands).

import 'dart:async';

import 'tool.dart';

/// Status of a tracked task.
enum TaskStatus {
  pending,
  running,
  completed,
  failed,
  cancelled;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

/// Type of tracked task.
enum TaskType { localBash, localAgent, remoteAgent }

/// A tracked background task.
class TrackedTask {
  final String id;
  final TaskType type;
  final String description;
  TaskStatus status;
  String? output;
  String? error;
  int? exitCode;
  DateTime startTime;
  DateTime? endTime;

  TrackedTask({
    required this.id,
    required this.type,
    required this.description,
    this.status = TaskStatus.pending,
    this.output,
    this.error,
    this.exitCode,
  }) : startTime = DateTime.now();

  void complete({String? output, int? exitCode}) {
    this.output = output;
    this.exitCode = exitCode;
    status = TaskStatus.completed;
    endTime = DateTime.now();
  }

  void fail(String error) {
    this.error = error;
    status = TaskStatus.failed;
    endTime = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
    'task_id': id,
    'task_type': type.name,
    'status': status.name,
    'description': description,
    if (output != null) 'output': output,
    if (error != null) 'error': error,
    if (exitCode != null) 'exitCode': exitCode,
  };
}

/// TaskOutput tool — retrieves results from background tasks.
class TaskOutputTool extends Tool {
  /// Task store — shared with other tools that create tasks.
  final Map<String, TrackedTask> tasks;

  TaskOutputTool({required this.tasks});

  @override
  String get name => 'TaskOutput';

  @override
  String get description =>
      'Retrieves the output of a background task. Can block until '
      'the task completes or return immediately.';

  @override
  bool get isReadOnly => true;

  @override
  bool get shouldDefer => true;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'task_id': {
        'type': 'string',
        'description': 'Task ID to retrieve output from',
      },
      'block': {
        'type': 'boolean',
        'description': 'Wait for completion (default: true)',
      },
      'timeout': {
        'type': 'number',
        'description': 'Max wait time in ms (default: 30000, max: 600000)',
      },
    },
    'required': ['task_id'],
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final taskId = input['task_id'] as String?;
    final block = input['block'] as bool? ?? true;
    final timeout = (input['timeout'] as num?)?.toInt() ?? 30000;

    if (taskId == null || taskId.isEmpty) {
      return ToolResult.error('Missing required parameter: task_id');
    }

    final task = tasks[taskId];
    if (task == null) {
      return ToolResult.error('Task not found: $taskId');
    }

    if (!block || task.status.isTerminal) {
      return _formatTaskResult(task);
    }

    // Blocking: wait for task completion
    final maxTimeout = timeout.clamp(0, 600000);
    final deadline = DateTime.now().add(Duration(milliseconds: maxTimeout));

    while (!task.status.isTerminal && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (!task.status.isTerminal) {
      return ToolResult.success(
        'Task "$taskId" did not complete within ${maxTimeout}ms.\n'
        'Current status: ${task.status.name}\n'
        'Use TaskOutput again to check later.',
        metadata: {'retrieval_status': 'timeout'},
      );
    }

    return _formatTaskResult(task);
  }

  ToolResult _formatTaskResult(TrackedTask task) {
    final buffer = StringBuffer();
    buffer.writeln('Task: ${task.id}');
    buffer.writeln('Type: ${task.type.name}');
    buffer.writeln('Status: ${task.status.name}');
    buffer.writeln('Description: ${task.description}');

    if (task.output != null) {
      buffer.writeln('\nOutput:');
      buffer.writeln(task.output);
    }
    if (task.error != null) {
      buffer.writeln('\nError: ${task.error}');
    }
    if (task.exitCode != null) {
      buffer.writeln('Exit code: ${task.exitCode}');
    }

    return ToolResult.success(
      buffer.toString(),
      metadata: {'retrieval_status': 'success', 'task': task.toJson()},
    );
  }
}
