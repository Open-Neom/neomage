// CoordinatorService — port of openclaude/src/coordinator/coordinatorMode.ts.
// Manages multi-agent orchestration, task distribution, result aggregation,
// and coordinated workflows between the main agent and sub-agents.

import 'dart:async';
import 'dart:convert';

// ─── Types ───

/// Coordinator mode.
enum CoordinatorMode {
  sequential, // Tasks run one at a time
  parallel, // Tasks run concurrently
  pipeline, // Output of one task feeds into next
  broadcast, // Same task sent to multiple agents
  consensus, // Multiple agents vote on result
}

/// Task priority.
enum TaskPriority {
  low,
  normal,
  high,
  critical,
}

/// Task status.
enum TaskStatus {
  pending,
  queued,
  assigned,
  running,
  completed,
  failed,
  cancelled,
  timeout,
  blocked, // Waiting on dependency
}

/// Agent capability.
enum AgentCapability {
  codeGeneration,
  codeReview,
  testing,
  documentation,
  debugging,
  refactoring,
  architecture,
  security,
  performance,
  devops,
  research,
  general,
}

/// A task to be distributed to an agent.
class CoordinatorTask {
  final String id;
  final String name;
  final String description;
  final String prompt;
  final TaskPriority priority;
  final TaskStatus status;
  final List<String> dependencies; // Task IDs this depends on
  final List<AgentCapability> requiredCapabilities;
  final String? assignedAgentId;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Duration? timeout;
  final Map<String, dynamic>? input;
  final String? output;
  final String? error;
  final int retryCount;
  final int maxRetries;
  final Map<String, dynamic>? metadata;

  const CoordinatorTask({
    required this.id,
    required this.name,
    required this.description,
    required this.prompt,
    this.priority = TaskPriority.normal,
    this.status = TaskStatus.pending,
    this.dependencies = const [],
    this.requiredCapabilities = const [],
    this.assignedAgentId,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.timeout,
    this.input,
    this.output,
    this.error,
    this.retryCount = 0,
    this.maxRetries = 2,
    this.metadata,
  });

  Duration? get elapsed =>
      startedAt != null ? (completedAt ?? DateTime.now()).difference(startedAt!) : null;

  bool get isDone =>
      status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.cancelled;

  CoordinatorTask copyWith({
    TaskStatus? status,
    String? assignedAgentId,
    DateTime? startedAt,
    DateTime? completedAt,
    String? output,
    String? error,
    int? retryCount,
  }) =>
      CoordinatorTask(
        id: id,
        name: name,
        description: description,
        prompt: prompt,
        priority: priority,
        status: status ?? this.status,
        dependencies: dependencies,
        requiredCapabilities: requiredCapabilities,
        assignedAgentId: assignedAgentId ?? this.assignedAgentId,
        createdAt: createdAt,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        timeout: timeout,
        input: input,
        output: output ?? this.output,
        error: error ?? this.error,
        retryCount: retryCount ?? this.retryCount,
        maxRetries: maxRetries,
        metadata: metadata,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'status': status.name,
        'priority': priority.name,
        'assignedAgentId': assignedAgentId,
        'createdAt': createdAt.toIso8601String(),
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        if (output != null) 'output': output,
        if (error != null) 'error': error,
        'retryCount': retryCount,
        'dependencies': dependencies,
      };
}

/// An agent available for task execution.
class CoordinatorAgent {
  final String id;
  final String name;
  final String? model;
  final Set<AgentCapability> capabilities;
  final int maxConcurrentTasks;
  final int currentTasks;
  final bool isAvailable;
  final DateTime registeredAt;
  final int completedTasks;
  final int failedTasks;
  final Duration averageLatency;

  const CoordinatorAgent({
    required this.id,
    required this.name,
    this.model,
    this.capabilities = const {},
    this.maxConcurrentTasks = 1,
    this.currentTasks = 0,
    this.isAvailable = true,
    required this.registeredAt,
    this.completedTasks = 0,
    this.failedTasks = 0,
    this.averageLatency = Duration.zero,
  });

  bool get hasCapacity => currentTasks < maxConcurrentTasks;
  double get successRate => completedTasks + failedTasks > 0
      ? completedTasks / (completedTasks + failedTasks)
      : 1.0;

  CoordinatorAgent copyWith({
    int? currentTasks,
    bool? isAvailable,
    int? completedTasks,
    int? failedTasks,
    Duration? averageLatency,
  }) =>
      CoordinatorAgent(
        id: id,
        name: name,
        model: model,
        capabilities: capabilities,
        maxConcurrentTasks: maxConcurrentTasks,
        currentTasks: currentTasks ?? this.currentTasks,
        isAvailable: isAvailable ?? this.isAvailable,
        registeredAt: registeredAt,
        completedTasks: completedTasks ?? this.completedTasks,
        failedTasks: failedTasks ?? this.failedTasks,
        averageLatency: averageLatency ?? this.averageLatency,
      );
}

/// A workflow definition (sequence of coordinated tasks).
class Workflow {
  final String id;
  final String name;
  final String description;
  final CoordinatorMode mode;
  final List<CoordinatorTask> tasks;
  final DateTime createdAt;
  final DateTime? completedAt;
  final Map<String, dynamic>? config;

  const Workflow({
    required this.id,
    required this.name,
    required this.description,
    required this.mode,
    required this.tasks,
    required this.createdAt,
    this.completedAt,
    this.config,
  });

  double get progress {
    if (tasks.isEmpty) return 1.0;
    return tasks.where((t) => t.isDone).length / tasks.length;
  }

  bool get isComplete => tasks.every((t) => t.isDone);
  bool get hasFailed => tasks.any((t) => t.status == TaskStatus.failed);

  int get completedCount =>
      tasks.where((t) => t.status == TaskStatus.completed).length;
  int get failedCount =>
      tasks.where((t) => t.status == TaskStatus.failed).length;
  int get pendingCount =>
      tasks.where((t) => !t.isDone).length;
}

/// Coordinator event.
sealed class CoordinatorEvent {
  const CoordinatorEvent();
}

class TaskAssigned extends CoordinatorEvent {
  final CoordinatorTask task;
  final CoordinatorAgent agent;
  const TaskAssigned(this.task, this.agent);
}

class TaskStarted extends CoordinatorEvent {
  final CoordinatorTask task;
  const TaskStarted(this.task);
}

class TaskCompleted extends CoordinatorEvent {
  final CoordinatorTask task;
  const TaskCompleted(this.task);
}

class TaskFailed extends CoordinatorEvent {
  final CoordinatorTask task;
  final String error;
  const TaskFailed(this.task, this.error);
}

class WorkflowCompleted extends CoordinatorEvent {
  final Workflow workflow;
  const WorkflowCompleted(this.workflow);
}

class AgentRegistered extends CoordinatorEvent {
  final CoordinatorAgent agent;
  const AgentRegistered(this.agent);
}

class AgentUnregistered extends CoordinatorEvent {
  final String agentId;
  const AgentUnregistered(this.agentId);
}

// ─── Task Decomposer ───

/// Decomposes complex prompts into discrete tasks.
class TaskDecomposer {
  int _taskCounter = 0;

  String _nextId() {
    _taskCounter++;
    return 'task_${DateTime.now().millisecondsSinceEpoch}_$_taskCounter';
  }

  /// Decompose a prompt into tasks based on structure.
  List<CoordinatorTask> decompose(String prompt, {CoordinatorMode mode = CoordinatorMode.sequential}) {
    final tasks = <CoordinatorTask>[];
    final now = DateTime.now();

    // Check for numbered list pattern.
    final numberedPattern = RegExp(r'^\d+[\.\)]\s+(.+)$', multiLine: true);
    final matches = numberedPattern.allMatches(prompt).toList();

    if (matches.length >= 2) {
      String? previousId;
      for (final match in matches) {
        final taskPrompt = match.group(1)!.trim();
        final taskId = _nextId();

        tasks.add(CoordinatorTask(
          id: taskId,
          name: _extractTaskName(taskPrompt),
          description: taskPrompt,
          prompt: taskPrompt,
          createdAt: now,
          dependencies: mode == CoordinatorMode.sequential && previousId != null
              ? [previousId]
              : [],
          requiredCapabilities: _inferCapabilities(taskPrompt),
        ));

        previousId = taskId;
      }
      return tasks;
    }

    // Check for bullet list pattern.
    final bulletPattern = RegExp(r'^[-*]\s+(.+)$', multiLine: true);
    final bulletMatches = bulletPattern.allMatches(prompt).toList();

    if (bulletMatches.length >= 2) {
      for (final match in bulletMatches) {
        final taskPrompt = match.group(1)!.trim();
        tasks.add(CoordinatorTask(
          id: _nextId(),
          name: _extractTaskName(taskPrompt),
          description: taskPrompt,
          prompt: taskPrompt,
          createdAt: now,
          requiredCapabilities: _inferCapabilities(taskPrompt),
        ));
      }
      return tasks;
    }

    // Check for "then"/"after"/"next" sequential markers.
    final sequentialParts = prompt.split(RegExp(r'\.\s+(?:Then|After that|Next|Finally|Lastly)', caseSensitive: false));
    if (sequentialParts.length >= 2) {
      String? previousId;
      for (final part in sequentialParts) {
        final taskPrompt = part.trim();
        if (taskPrompt.isEmpty) continue;
        final taskId = _nextId();

        tasks.add(CoordinatorTask(
          id: taskId,
          name: _extractTaskName(taskPrompt),
          description: taskPrompt,
          prompt: taskPrompt,
          createdAt: now,
          dependencies: previousId != null ? [previousId] : [],
          requiredCapabilities: _inferCapabilities(taskPrompt),
        ));

        previousId = taskId;
      }
      return tasks;
    }

    // Single task.
    tasks.add(CoordinatorTask(
      id: _nextId(),
      name: _extractTaskName(prompt),
      description: prompt,
      prompt: prompt,
      createdAt: now,
      requiredCapabilities: _inferCapabilities(prompt),
    ));

    return tasks;
  }

  String _extractTaskName(String prompt) {
    // Take first sentence or first 50 chars.
    final firstSentence = RegExp(r'^[^.!?]+[.!?]?').firstMatch(prompt);
    final name = firstSentence?.group(0) ?? prompt;
    return name.length > 50 ? '${name.substring(0, 47)}...' : name;
  }

  Set<AgentCapability> _inferCapabilities(String prompt) {
    final lower = prompt.toLowerCase();
    final caps = <AgentCapability>{};

    if (lower.contains('test') || lower.contains('spec')) {
      caps.add(AgentCapability.testing);
    }
    if (lower.contains('review') || lower.contains('feedback')) {
      caps.add(AgentCapability.codeReview);
    }
    if (lower.contains('document') || lower.contains('readme') || lower.contains('docs')) {
      caps.add(AgentCapability.documentation);
    }
    if (lower.contains('debug') || lower.contains('fix') || lower.contains('error')) {
      caps.add(AgentCapability.debugging);
    }
    if (lower.contains('refactor') || lower.contains('clean') || lower.contains('improve')) {
      caps.add(AgentCapability.refactoring);
    }
    if (lower.contains('security') || lower.contains('vulnerability') || lower.contains('audit')) {
      caps.add(AgentCapability.security);
    }
    if (lower.contains('performance') || lower.contains('optimize') || lower.contains('benchmark')) {
      caps.add(AgentCapability.performance);
    }
    if (lower.contains('deploy') || lower.contains('ci') || lower.contains('docker')) {
      caps.add(AgentCapability.devops);
    }
    if (lower.contains('architecture') || lower.contains('design') || lower.contains('plan')) {
      caps.add(AgentCapability.architecture);
    }
    if (lower.contains('research') || lower.contains('investigate') || lower.contains('analyze')) {
      caps.add(AgentCapability.research);
    }

    if (caps.isEmpty) caps.add(AgentCapability.general);
    return caps;
  }
}

// ─── Scheduler ───

/// Schedules tasks to agents based on capability, capacity, and priority.
class TaskScheduler {
  /// Find the best agent for a task.
  CoordinatorAgent? findBestAgent(
    CoordinatorTask task,
    List<CoordinatorAgent> agents,
  ) {
    final candidates = agents
        .where((a) => a.isAvailable && a.hasCapacity)
        .toList();

    if (candidates.isEmpty) return null;

    // Score each candidate.
    final scored = candidates.map((agent) {
      double score = 0;

      // Capability match.
      if (task.requiredCapabilities.isNotEmpty) {
        final matchCount = task.requiredCapabilities
            .where((c) => agent.capabilities.contains(c))
            .length;
        score += (matchCount / task.requiredCapabilities.length) * 50;
      } else {
        score += 25; // No specific requirement.
      }

      // Capacity (prefer less loaded agents).
      score += (1.0 - agent.currentTasks / agent.maxConcurrentTasks) * 20;

      // Success rate.
      score += agent.successRate * 15;

      // Lower latency is better.
      if (agent.averageLatency.inMilliseconds > 0) {
        score += (10000 / (agent.averageLatency.inMilliseconds + 1)).clamp(0, 15);
      } else {
        score += 10;
      }

      return (agent: agent, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.first.agent;
  }

  /// Order tasks by priority and dependencies.
  List<CoordinatorTask> prioritize(List<CoordinatorTask> tasks) {
    final sorted = List<CoordinatorTask>.from(tasks);
    sorted.sort((a, b) {
      // Critical tasks first.
      final priorityCmp = b.priority.index.compareTo(a.priority.index);
      if (priorityCmp != 0) return priorityCmp;

      // Tasks with fewer dependencies first.
      final depCmp = a.dependencies.length.compareTo(b.dependencies.length);
      if (depCmp != 0) return depCmp;

      // Earlier created tasks first.
      return a.createdAt.compareTo(b.createdAt);
    });
    return sorted;
  }

  /// Check if a task's dependencies are all completed.
  bool areDependenciesMet(
    CoordinatorTask task,
    Map<String, CoordinatorTask> allTasks,
  ) {
    for (final depId in task.dependencies) {
      final dep = allTasks[depId];
      if (dep == null || dep.status != TaskStatus.completed) return false;
    }
    return true;
  }
}

// ─── Result Aggregator ───

/// Aggregates results from multiple tasks/agents.
class ResultAggregator {
  /// Combine results from parallel tasks.
  String combineResults(List<CoordinatorTask> tasks) {
    final buffer = StringBuffer();
    final completed = tasks.where((t) => t.status == TaskStatus.completed).toList();
    final failed = tasks.where((t) => t.status == TaskStatus.failed).toList();

    if (completed.isNotEmpty) {
      buffer.writeln('## Completed Tasks (${completed.length}/${tasks.length})');
      buffer.writeln();
      for (final task in completed) {
        buffer.writeln('### ${task.name}');
        buffer.writeln(task.output ?? '(no output)');
        buffer.writeln();
      }
    }

    if (failed.isNotEmpty) {
      buffer.writeln('## Failed Tasks (${failed.length})');
      buffer.writeln();
      for (final task in failed) {
        buffer.writeln('### ${task.name}');
        buffer.writeln('Error: ${task.error ?? 'Unknown error'}');
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  /// Merge pipeline outputs (output of task N becomes context for task N+1).
  String buildPipelineContext(List<CoordinatorTask> completedTasks) {
    final buffer = StringBuffer();
    buffer.writeln('Previous step results:');
    buffer.writeln();

    for (final task in completedTasks) {
      buffer.writeln('--- ${task.name} ---');
      buffer.writeln(task.output ?? '');
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Find consensus from multiple agent responses.
  String findConsensus(List<String> responses) {
    if (responses.isEmpty) return '';
    if (responses.length == 1) return responses.first;

    // Simple consensus: find common themes.
    final buffer = StringBuffer();
    buffer.writeln('Multiple agents provided responses:');
    buffer.writeln();

    for (int i = 0; i < responses.length; i++) {
      buffer.writeln('### Agent ${i + 1}');
      buffer.writeln(responses[i]);
      buffer.writeln();
    }

    return buffer.toString();
  }
}

// ─── Coordinator Service ───

/// Main coordinator service for multi-agent task orchestration.
class CoordinatorServiceFull {
  final Map<String, CoordinatorAgent> _agents = {};
  final Map<String, CoordinatorTask> _tasks = {};
  final Map<String, Workflow> _workflows = {};
  final TaskDecomposer _decomposer = TaskDecomposer();
  final TaskScheduler _scheduler = TaskScheduler();
  final ResultAggregator _aggregator = ResultAggregator();
  final StreamController<CoordinatorEvent> _eventController =
      StreamController<CoordinatorEvent>.broadcast();
  Timer? _schedulerTimer;

  /// Event stream.
  Stream<CoordinatorEvent> get events => _eventController.stream;

  /// All registered agents.
  List<CoordinatorAgent> get agents => _agents.values.toList();

  /// All tasks.
  List<CoordinatorTask> get tasks => _tasks.values.toList();

  /// Active workflows.
  List<Workflow> get workflows => _workflows.values.toList();

  // ─── Agent Management ───

  /// Register an agent.
  void registerAgent(CoordinatorAgent agent) {
    _agents[agent.id] = agent;
    _eventController.add(AgentRegistered(agent));
  }

  /// Unregister an agent.
  void unregisterAgent(String agentId) {
    _agents.remove(agentId);
    _eventController.add(AgentUnregistered(agentId));
  }

  /// Update agent status.
  void updateAgent(String agentId, {bool? isAvailable, int? currentTasks}) {
    final agent = _agents[agentId];
    if (agent == null) return;
    _agents[agentId] = agent.copyWith(
      isAvailable: isAvailable,
      currentTasks: currentTasks,
    );
  }

  // ─── Workflow Management ───

  /// Create and start a workflow.
  Future<Workflow> createWorkflow({
    required String name,
    required String prompt,
    CoordinatorMode mode = CoordinatorMode.sequential,
    Map<String, dynamic>? config,
  }) async {
    final now = DateTime.now();
    final tasks = _decomposer.decompose(prompt, mode: mode);

    // Register tasks.
    for (final task in tasks) {
      _tasks[task.id] = task;
    }

    final workflow = Workflow(
      id: 'wf_${now.millisecondsSinceEpoch}',
      name: name,
      description: prompt,
      mode: mode,
      tasks: tasks,
      createdAt: now,
      config: config,
    );

    _workflows[workflow.id] = workflow;

    // Start scheduling.
    _startScheduling();

    return workflow;
  }

  /// Cancel a workflow.
  void cancelWorkflow(String workflowId) {
    final workflow = _workflows[workflowId];
    if (workflow == null) return;

    for (final task in workflow.tasks) {
      if (!task.isDone) {
        _tasks[task.id] = task.copyWith(status: TaskStatus.cancelled);
      }
    }
  }

  /// Get workflow status.
  Workflow? getWorkflow(String workflowId) => _workflows[workflowId];

  // ─── Task Management ───

  /// Submit a single task.
  CoordinatorTask submitTask({
    required String name,
    required String prompt,
    TaskPriority priority = TaskPriority.normal,
    List<String> dependencies = const [],
    Duration? timeout,
  }) {
    final task = CoordinatorTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: prompt,
      prompt: prompt,
      priority: priority,
      dependencies: dependencies,
      timeout: timeout,
      createdAt: DateTime.now(),
      requiredCapabilities: _decomposer._inferCapabilities(prompt),
    );

    _tasks[task.id] = task;
    _startScheduling();
    return task;
  }

  /// Report task completion (called by agent after finishing).
  void completeTask(String taskId, {required String output}) {
    final task = _tasks[taskId];
    if (task == null) return;

    final completed = task.copyWith(
      status: TaskStatus.completed,
      completedAt: DateTime.now(),
      output: output,
    );

    _tasks[taskId] = completed;
    _eventController.add(TaskCompleted(completed));

    // Update agent stats.
    if (task.assignedAgentId != null) {
      final agent = _agents[task.assignedAgentId];
      if (agent != null) {
        _agents[task.assignedAgentId!] = agent.copyWith(
          currentTasks: agent.currentTasks - 1,
          completedTasks: agent.completedTasks + 1,
          averageLatency: _updateAverageLatency(
            agent.averageLatency,
            agent.completedTasks,
            completed.elapsed ?? Duration.zero,
          ),
        );
      }
    }

    // Check if any workflow is complete.
    _checkWorkflowCompletion();

    // Schedule next tasks.
    _runScheduler();
  }

  /// Report task failure.
  void failTask(String taskId, {required String error}) {
    final task = _tasks[taskId];
    if (task == null) return;

    // Check if we should retry.
    if (task.retryCount < task.maxRetries) {
      _tasks[taskId] = task.copyWith(
        status: TaskStatus.pending,
        retryCount: task.retryCount + 1,
        error: error,
        assignedAgentId: null, // Allow reassignment
      );
      _runScheduler();
      return;
    }

    final failed = task.copyWith(
      status: TaskStatus.failed,
      completedAt: DateTime.now(),
      error: error,
    );

    _tasks[taskId] = failed;
    _eventController.add(TaskFailed(failed, error));

    // Update agent stats.
    if (task.assignedAgentId != null) {
      final agent = _agents[task.assignedAgentId];
      if (agent != null) {
        _agents[task.assignedAgentId!] = agent.copyWith(
          currentTasks: agent.currentTasks - 1,
          failedTasks: agent.failedTasks + 1,
        );
      }
    }

    _checkWorkflowCompletion();
  }

  /// Cancel a task.
  void cancelTask(String taskId) {
    final task = _tasks[taskId];
    if (task == null || task.isDone) return;

    _tasks[taskId] = task.copyWith(
      status: TaskStatus.cancelled,
      completedAt: DateTime.now(),
    );

    if (task.assignedAgentId != null) {
      final agent = _agents[task.assignedAgentId];
      if (agent != null) {
        _agents[task.assignedAgentId!] = agent.copyWith(
          currentTasks: agent.currentTasks - 1,
        );
      }
    }
  }

  /// Get task by ID.
  CoordinatorTask? getTask(String taskId) => _tasks[taskId];

  /// Get aggregated results for a workflow.
  String getWorkflowResults(String workflowId) {
    final workflow = _workflows[workflowId];
    if (workflow == null) return '';
    return _aggregator.combineResults(workflow.tasks);
  }

  // ─── Scheduling ───

  void _startScheduling() {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _runScheduler(),
    );
  }

  void _runScheduler() {
    // Find pending tasks with met dependencies.
    final pendingTasks = _tasks.values
        .where((t) => t.status == TaskStatus.pending)
        .where((t) => _scheduler.areDependenciesMet(t, _tasks))
        .toList();

    if (pendingTasks.isEmpty) {
      // Check if all tasks are done.
      if (_tasks.values.every((t) => t.isDone)) {
        _schedulerTimer?.cancel();
      }
      return;
    }

    final prioritized = _scheduler.prioritize(pendingTasks);
    final availableAgents = _agents.values.toList();

    for (final task in prioritized) {
      final agent = _scheduler.findBestAgent(task, availableAgents);
      if (agent == null) break; // No available agents.

      // Assign task.
      _tasks[task.id] = task.copyWith(
        status: TaskStatus.assigned,
        assignedAgentId: agent.id,
        startedAt: DateTime.now(),
      );

      _agents[agent.id] = agent.copyWith(
        currentTasks: agent.currentTasks + 1,
      );

      _eventController.add(TaskAssigned(_tasks[task.id]!, agent));
    }
  }

  void _checkWorkflowCompletion() {
    for (final entry in _workflows.entries) {
      final workflow = entry.value;
      if (workflow.completedAt != null) continue;

      final allDone = workflow.tasks.every((t) {
        final current = _tasks[t.id];
        return current?.isDone ?? false;
      });

      if (allDone) {
        _workflows[entry.key] = Workflow(
          id: workflow.id,
          name: workflow.name,
          description: workflow.description,
          mode: workflow.mode,
          tasks: workflow.tasks.map((t) => _tasks[t.id] ?? t).toList(),
          createdAt: workflow.createdAt,
          completedAt: DateTime.now(),
          config: workflow.config,
        );
        _eventController.add(WorkflowCompleted(_workflows[entry.key]!));
      }
    }
  }

  Duration _updateAverageLatency(
      Duration current, int count, Duration newLatency) {
    if (count <= 0) return newLatency;
    final totalMs =
        current.inMilliseconds * count + newLatency.inMilliseconds;
    return Duration(milliseconds: totalMs ~/ (count + 1));
  }

  /// Get coordinator statistics.
  Map<String, dynamic> getStats() => {
        'agents': _agents.length,
        'availableAgents': _agents.values.where((a) => a.isAvailable && a.hasCapacity).length,
        'totalTasks': _tasks.length,
        'pendingTasks': _tasks.values.where((t) => t.status == TaskStatus.pending).length,
        'runningTasks': _tasks.values.where((t) => t.status == TaskStatus.running || t.status == TaskStatus.assigned).length,
        'completedTasks': _tasks.values.where((t) => t.status == TaskStatus.completed).length,
        'failedTasks': _tasks.values.where((t) => t.status == TaskStatus.failed).length,
        'workflows': _workflows.length,
        'activeWorkflows': _workflows.values.where((w) => w.completedAt == null).length,
      };

  /// Dispose resources.
  void dispose() {
    _schedulerTimer?.cancel();
    _eventController.close();
  }
}
