// Coordinator service — port of neom_claw/src/coordinator.
// Multi-agent coordination mode for complex tasks.

import '../tools/agent_tool.dart';

/// Coordinator mode — manages multiple agents working together.
enum CoordinatorState {
  /// Normal single-agent mode.
  inactive,

  /// Coordinator is active, managing sub-agents.
  active,

  /// Coordinator is waiting for sub-agent results.
  waiting,

  /// Coordinator is synthesizing results.
  synthesizing,
}

/// A task assigned to a sub-agent by the coordinator.
class CoordinatorTask {
  final String id;
  final String agentId;
  final String description;
  final String prompt;
  CoordinatorTaskStatus status;
  String? result;
  DateTime startTime;
  DateTime? endTime;

  CoordinatorTask({
    required this.id,
    required this.agentId,
    required this.description,
    required this.prompt,
    this.status = CoordinatorTaskStatus.pending,
  }) : startTime = DateTime.now();
}

/// Status of a coordinator task.
enum CoordinatorTaskStatus { pending, running, completed, failed }

/// Coordinator service — orchestrates multiple agents.
class CoordinatorService {
  final AgentTool agentTool;
  CoordinatorState _state = CoordinatorState.inactive;
  final List<CoordinatorTask> _tasks = [];

  CoordinatorService({required this.agentTool});

  /// Current state.
  CoordinatorState get state => _state;

  /// All tracked tasks.
  List<CoordinatorTask> get tasks => List.unmodifiable(_tasks);

  /// Active tasks.
  List<CoordinatorTask> get activeTasks =>
      _tasks.where((t) => t.status == CoordinatorTaskStatus.running).toList();

  /// Whether coordinator mode is active.
  bool get isActive => _state != CoordinatorState.inactive;

  /// Activate coordinator mode.
  void activate() {
    _state = CoordinatorState.active;
  }

  /// Deactivate coordinator mode.
  void deactivate() {
    _state = CoordinatorState.inactive;
    _tasks.clear();
  }

  /// Spawn a sub-agent task.
  Future<CoordinatorTask> spawnTask({
    required String description,
    required String prompt,
    String agentType = 'general-purpose',
  }) async {
    final taskId = 'coord_${DateTime.now().millisecondsSinceEpoch}';
    final agentId = 'agent_$taskId';

    final task = CoordinatorTask(
      id: taskId,
      agentId: agentId,
      description: description,
      prompt: prompt,
      status: CoordinatorTaskStatus.running,
    );
    _tasks.add(task);
    _state = CoordinatorState.waiting;

    // Execute via AgentTool
    try {
      final result = await agentTool.execute({
        'prompt': prompt,
        'description': description,
        'subagent_type': agentType,
        'run_in_background': true,
      });

      if (result.isError) {
        task.status = CoordinatorTaskStatus.failed;
        task.result = result.content;
      }
    } catch (e) {
      task.status = CoordinatorTaskStatus.failed;
      task.result = 'Error: $e';
    }

    return task;
  }

  /// Complete a task with a result.
  void completeTask(String taskId, String result) {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('Task not found: $taskId'),
    );
    task.status = CoordinatorTaskStatus.completed;
    task.result = result;
    task.endTime = DateTime.now();

    // Check if all tasks are done
    if (_tasks.every((t) => t.status.index >= 2)) {
      _state = CoordinatorState.synthesizing;
    }
  }

  /// Build a synthesis prompt from completed task results.
  String buildSynthesisPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('All sub-agent tasks have completed. Results:');
    buffer.writeln();

    for (final task in _tasks) {
      buffer.writeln('## ${task.description}');
      buffer.writeln('Status: ${task.status.name}');
      if (task.result != null) {
        buffer.writeln(task.result);
      }
      buffer.writeln();
    }

    buffer.writeln('Synthesize these results into a coherent response.');
    return buffer.toString();
  }
}
