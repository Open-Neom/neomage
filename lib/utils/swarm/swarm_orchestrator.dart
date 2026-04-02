import 'dart:async';
import 'dart:collection';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Role an agent plays within a swarm.
enum AgentRole {
  coordinator,
  researcher,
  implementer,
  reviewer,
  tester,
  planner,
}

/// Lifecycle status of a task.
enum TaskStatus {
  pending,
  running,
  completed,
  failed,
  cancelled,
  blocked,
}

// ---------------------------------------------------------------------------
// SwarmMessage
// ---------------------------------------------------------------------------

/// A message passed between agents via the [MessageBus].
class SwarmMessage {
  SwarmMessage({
    required this.fromAgentId,
    required this.toAgentId,
    required this.content,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  })  : metadata = metadata ?? {},
        timestamp = timestamp ?? DateTime.now();

  final String fromAgentId;

  /// Use `'*'` to broadcast to all agents.
  final String toAgentId;
  final String content;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  bool get isBroadcast => toAgentId == '*';

  Map<String, dynamic> toJson() => {
        'from': fromAgentId,
        'to': toAgentId,
        'content': content,
        'metadata': metadata,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// MessageBus
// ---------------------------------------------------------------------------

/// Simple pub/sub message bus for inter-agent communication.
class MessageBus {
  final Map<String, List<void Function(SwarmMessage)>> _subscriptions = {};
  final List<SwarmMessage> _history = [];

  /// Subscribe [agentId] to incoming messages.
  void subscribe(String agentId, void Function(SwarmMessage) handler) {
    _subscriptions.putIfAbsent(agentId, () => []).add(handler);
  }

  /// Remove all subscriptions for [agentId].
  void unsubscribe(String agentId) {
    _subscriptions.remove(agentId);
  }

  /// Publish a message. Delivers to direct recipient and broadcasts.
  void publish(SwarmMessage message) {
    _history.add(message);

    if (message.isBroadcast) {
      for (final entry in _subscriptions.entries) {
        if (entry.key != message.fromAgentId) {
          for (final handler in entry.value) {
            handler(message);
          }
        }
      }
    } else {
      final handlers = _subscriptions[message.toAgentId];
      if (handlers != null) {
        for (final handler in handlers) {
          handler(message);
        }
      }
    }
  }

  /// All messages sent so far.
  List<SwarmMessage> get history => List.unmodifiable(_history);

  /// Messages sent to or from a specific agent.
  List<SwarmMessage> messagesFor(String agentId) {
    return _history
        .where((m) =>
            m.fromAgentId == agentId ||
            m.toAgentId == agentId ||
            m.isBroadcast)
        .toList();
  }

  void clear() {
    _history.clear();
    _subscriptions.clear();
  }
}

// ---------------------------------------------------------------------------
// SwarmTask
// ---------------------------------------------------------------------------

/// A unit of work that can be assigned to a [SwarmAgent].
class SwarmTask {
  SwarmTask({
    required this.id,
    required this.description,
    List<String>? dependencies,
    this.assignedAgentId,
    this.maxRetries = 2,
    this.timeoutSeconds = 300,
  })  : dependencies = dependencies ?? [],
        status = TaskStatus.pending,
        _retryCount = 0;

  final String id;
  final String description;
  final List<String> dependencies;
  final int maxRetries;
  final int timeoutSeconds;

  TaskStatus status;
  String? assignedAgentId;
  dynamic result;
  String? error;
  DateTime? startedAt;
  DateTime? completedAt;
  int _retryCount;

  int get retryCount => _retryCount;

  /// Duration the task has been (or was) running.
  Duration? get elapsed {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  /// Whether the task can be retried after a failure.
  bool get canRetry => _retryCount < maxRetries;

  void markRunning(String agentId) {
    status = TaskStatus.running;
    assignedAgentId = agentId;
    startedAt = DateTime.now();
  }

  void markCompleted(dynamic taskResult) {
    status = TaskStatus.completed;
    result = taskResult;
    completedAt = DateTime.now();
  }

  void markFailed(String errorMsg) {
    _retryCount++;
    if (canRetry) {
      // Reset to pending for retry.
      status = TaskStatus.pending;
      assignedAgentId = null;
      startedAt = null;
    } else {
      status = TaskStatus.failed;
      completedAt = DateTime.now();
    }
    error = errorMsg;
  }

  void markCancelled() {
    status = TaskStatus.cancelled;
    completedAt = DateTime.now();
  }

  void markBlocked() {
    status = TaskStatus.blocked;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'status': status.name,
        'dependencies': dependencies,
        'assignedAgentId': assignedAgentId,
        'retryCount': _retryCount,
        'error': error,
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// SwarmAgent
// ---------------------------------------------------------------------------

/// An individual agent in the swarm.
class SwarmAgent {
  SwarmAgent({
    required this.id,
    required this.name,
    required this.role,
    this.model = 'claude-sonnet-4-20250514',
    this.systemPrompt = '',
    List<String>? tools,
  })  : tools = tools ?? [],
        _idle = true;

  final String id;
  final String name;
  final AgentRole role;
  final String model;
  final String systemPrompt;
  final List<String> tools;

  bool _idle;
  String? _currentTaskId;
  final List<String> _completedTaskIds = [];

  bool get isIdle => _idle;
  String? get currentTaskId => _currentTaskId;
  List<String> get completedTaskIds => List.unmodifiable(_completedTaskIds);

  void assignTask(String taskId) {
    _idle = false;
    _currentTaskId = taskId;
  }

  void completeTask() {
    if (_currentTaskId != null) {
      _completedTaskIds.add(_currentTaskId!);
    }
    _idle = true;
    _currentTaskId = null;
  }

  void releaseTask() {
    _idle = true;
    _currentTaskId = null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
        'model': model,
        'idle': _idle,
        'currentTaskId': _currentTaskId,
        'completedTasks': _completedTaskIds.length,
      };
}

// ---------------------------------------------------------------------------
// AgentContext
// ---------------------------------------------------------------------------

/// Context made available to an agent while it executes a task.
class AgentContext {
  AgentContext({
    required this.agent,
    required this.task,
    required this.messageBus,
    Map<String, dynamic>? sharedMemory,
  }) : sharedMemory = sharedMemory ?? {};

  final SwarmAgent agent;
  final SwarmTask task;
  final MessageBus messageBus;

  /// Shared key-value store visible to all agents.
  final Map<String, dynamic> sharedMemory;

  /// Send a message from this agent.
  void sendMessage(String toAgentId, String content,
      {Map<String, dynamic>? metadata}) {
    messageBus.publish(SwarmMessage(
      fromAgentId: agent.id,
      toAgentId: toAgentId,
      content: content,
      metadata: metadata,
    ));
  }

  /// Broadcast a message to every other agent.
  void broadcast(String content, {Map<String, dynamic>? metadata}) {
    sendMessage('*', content, metadata: metadata);
  }
}

// ---------------------------------------------------------------------------
// DependencyGraph
// ---------------------------------------------------------------------------

/// Directed acyclic graph (DAG) of task dependencies with cycle detection and
/// topological ordering.
class DependencyGraph {
  final Map<String, Set<String>> _adjacency = {};

  /// Register a node (task id).
  void addNode(String id) {
    _adjacency.putIfAbsent(id, () => {});
  }

  /// Declare that [id] depends on [dependsOn] (edge dependsOn -> id).
  void addEdge(String id, String dependsOn) {
    addNode(id);
    addNode(dependsOn);
    _adjacency[dependsOn]!.add(id);
  }

  /// Build the graph from a list of tasks.
  void buildFromTasks(List<SwarmTask> tasks) {
    for (final task in tasks) {
      addNode(task.id);
      for (final dep in task.dependencies) {
        addEdge(task.id, dep);
      }
    }
  }

  /// Detect cycles using DFS colouring. Returns `true` if a cycle exists.
  bool hasCycle() {
    // 0 = white, 1 = grey, 2 = black
    final colour = <String, int>{for (final k in _adjacency.keys) k: 0};

    bool dfs(String node) {
      colour[node] = 1;
      for (final neighbour in _adjacency[node]!) {
        final c = colour[neighbour] ?? 0;
        if (c == 1) return true; // back-edge => cycle
        if (c == 0 && dfs(neighbour)) return true;
      }
      colour[node] = 2;
      return false;
    }

    for (final node in _adjacency.keys) {
      if (colour[node] == 0 && dfs(node)) return true;
    }
    return false;
  }

  /// Return nodes with no incoming edges (ready to run).
  Set<String> roots() {
    final allNodes = _adjacency.keys.toSet();
    final hasIncoming = <String>{};
    for (final neighbours in _adjacency.values) {
      hasIncoming.addAll(neighbours);
    }
    return allNodes.difference(hasIncoming);
  }

  /// Successors (dependents) of [node].
  Set<String> successors(String node) =>
      _adjacency[node] ?? <String>{};

  /// Predecessors (dependencies) of [node].
  Set<String> predecessors(String node) {
    final result = <String>{};
    for (final entry in _adjacency.entries) {
      if (entry.value.contains(node)) {
        result.add(entry.key);
      }
    }
    return result;
  }
}

/// Topologically sort a list of tasks according to their dependencies.
/// Throws [StateError] when a dependency cycle is detected.
List<SwarmTask> topologicalSort(List<SwarmTask> tasks) {
  final taskMap = {for (final t in tasks) t.id: t};
  // In-degree count per task.
  final inDegree = <String, int>{for (final t in tasks) t.id: 0};

  for (final task in tasks) {
    for (final dep in task.dependencies) {
      if (taskMap.containsKey(dep)) {
        // dep -> task: task has an incoming edge from dep.
        inDegree[task.id] = (inDegree[task.id] ?? 0) + 1;
      }
    }
  }

  final queue = Queue<String>();
  for (final entry in inDegree.entries) {
    if (entry.value == 0) queue.add(entry.key);
  }

  final sorted = <SwarmTask>[];
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    sorted.add(taskMap[current]!);

    // For each task that depends on `current`, decrement in-degree.
    for (final task in tasks) {
      if (task.dependencies.contains(current)) {
        inDegree[task.id] = inDegree[task.id]! - 1;
        if (inDegree[task.id] == 0) {
          queue.add(task.id);
        }
      }
    }
  }

  if (sorted.length != tasks.length) {
    throw StateError(
      'Dependency cycle detected: could not topologically sort '
      '${tasks.length} tasks (only ${sorted.length} resolved).',
    );
  }
  return sorted;
}

// ---------------------------------------------------------------------------
// SwarmProgress
// ---------------------------------------------------------------------------

/// Snapshot of overall swarm execution progress.
class SwarmProgress {
  SwarmProgress({
    required this.total,
    required this.completed,
    required this.failed,
    required this.running,
    required this.pending,
    required this.cancelled,
    required this.blocked,
  });

  final int total;
  final int completed;
  final int failed;
  final int running;
  final int pending;
  final int cancelled;
  final int blocked;

  /// Fraction of completed tasks (0.0 to 1.0).
  double get completionRate => total == 0 ? 0 : completed / total;

  bool get isFinished => (completed + failed + cancelled) == total;

  Map<String, dynamic> toJson() => {
        'total': total,
        'completed': completed,
        'failed': failed,
        'running': running,
        'pending': pending,
        'cancelled': cancelled,
        'blocked': blocked,
        'completionRate': completionRate,
      };

  @override
  String toString() =>
      'SwarmProgress(total=$total, completed=$completed, '
      'failed=$failed, running=$running, pending=$pending)';
}

// ---------------------------------------------------------------------------
// SwarmResult
// ---------------------------------------------------------------------------

/// Final result of a swarm execution.
class SwarmResult {
  SwarmResult({
    required this.success,
    required this.progress,
    required this.taskResults,
    required this.duration,
    this.error,
  });

  final bool success;
  final SwarmProgress progress;

  /// Map from task id to its result value.
  final Map<String, dynamic> taskResults;
  final Duration duration;
  final String? error;

  Map<String, dynamic> toJson() => {
        'success': success,
        'progress': progress.toJson(),
        'taskResults': taskResults,
        'durationMs': duration.inMilliseconds,
        if (error != null) 'error': error,
      };
}

// ---------------------------------------------------------------------------
// SwarmConfig
// ---------------------------------------------------------------------------

/// Configuration for a [SwarmOrchestrator].
class SwarmConfig {
  SwarmConfig({
    this.maxAgents = 10,
    this.maxDepth = 5,
    this.defaultTimeoutSeconds = 300,
    this.enableWorkStealing = true,
    this.maxRetries = 2,
    Map<AgentRole, String>? modelPerRole,
  }) : modelPerRole = modelPerRole ??
            {
              AgentRole.coordinator: 'claude-sonnet-4-20250514',
              AgentRole.researcher: 'claude-sonnet-4-20250514',
              AgentRole.implementer: 'claude-sonnet-4-20250514',
              AgentRole.reviewer: 'claude-sonnet-4-20250514',
              AgentRole.tester: 'claude-sonnet-4-20250514',
              AgentRole.planner: 'claude-sonnet-4-20250514',
            };

  final int maxAgents;
  final int maxDepth;
  final int defaultTimeoutSeconds;
  final bool enableWorkStealing;
  final int maxRetries;

  /// Model identifier to use for each agent role.
  final Map<AgentRole, String> modelPerRole;

  /// Look up the model to use for a given role.
  String modelFor(AgentRole role) =>
      modelPerRole[role] ?? 'claude-sonnet-4-20250514';
}

// ---------------------------------------------------------------------------
// SwarmOrchestrator
// ---------------------------------------------------------------------------

/// Orchestrates a swarm of agents executing interdependent tasks.
class SwarmOrchestrator {
  SwarmOrchestrator({
    required SwarmConfig config,
    Future<dynamic> Function(AgentContext)? executor,
  })  : _config = config,
        _executor = executor ?? _defaultExecutor;

  final SwarmConfig _config;
  final Future<dynamic> Function(AgentContext) _executor;
  final Map<String, SwarmAgent> _agents = {};
  final Map<String, SwarmTask> _tasks = {};
  final MessageBus _messageBus = MessageBus();
  final Map<String, dynamic> _sharedMemory = {};
  final DependencyGraph _graph = DependencyGraph();
  bool _cancelled = false;
  int _agentCounter = 0;

  /// Message bus used by agents.
  MessageBus get messageBus => _messageBus;

  /// Read-only view of current agents.
  Map<String, SwarmAgent> get agents => Map.unmodifiable(_agents);

  /// Read-only view of current tasks.
  Map<String, SwarmTask> get tasks => Map.unmodifiable(_tasks);

  // ---- Agent management ----------------------------------------------------

  /// Create and register a new agent.
  SwarmAgent createAgent({
    required String name,
    required AgentRole role,
    String? model,
    String systemPrompt = '',
    List<String>? tools,
  }) {
    if (_agents.length >= _config.maxAgents) {
      throw StateError(
        'Cannot create agent: maximum of ${_config.maxAgents} agents reached.',
      );
    }

    _agentCounter++;
    final id = 'agent_$_agentCounter';
    final agent = SwarmAgent(
      id: id,
      name: name,
      role: role,
      model: model ?? _config.modelFor(role),
      systemPrompt: systemPrompt,
      tools: tools,
    );
    _agents[id] = agent;
    _messageBus.subscribe(id, (_) {}); // default no-op subscription
    return agent;
  }

  /// Remove an idle agent from the swarm.
  bool removeAgent(String agentId) {
    final agent = _agents[agentId];
    if (agent == null) return false;
    if (!agent.isIdle) return false;
    _agents.remove(agentId);
    _messageBus.unsubscribe(agentId);
    return true;
  }

  // ---- Task management -----------------------------------------------------

  /// Register a task to be executed.
  SwarmTask assignTask({
    required String id,
    required String description,
    List<String>? dependencies,
    String? agentId,
    int? maxRetries,
    int? timeoutSeconds,
  }) {
    final task = SwarmTask(
      id: id,
      description: description,
      dependencies: dependencies,
      assignedAgentId: agentId,
      maxRetries: maxRetries ?? _config.maxRetries,
      timeoutSeconds: timeoutSeconds ?? _config.defaultTimeoutSeconds,
    );
    _tasks[id] = task;
    return task;
  }

  // ---- Execution -----------------------------------------------------------

  /// Run all registered tasks, respecting dependency order. Returns the
  /// aggregated [SwarmResult] once every task has completed (or failed).
  Future<SwarmResult> runSwarm() async {
    _cancelled = false;
    final stopwatch = Stopwatch()..start();

    // Build dependency graph and validate.
    _graph.buildFromTasks(_tasks.values.toList());
    if (_graph.hasCycle()) {
      stopwatch.stop();
      return SwarmResult(
        success: false,
        progress: getProgress(),
        taskResults: {},
        duration: stopwatch.elapsed,
        error: 'Dependency cycle detected in task graph.',
      );
    }

    // Initial dependency-blocked check.
    _updateBlockedTasks();

    // Main execution loop.
    while (!_isComplete() && !_cancelled) {
      _updateBlockedTasks();

      // Find tasks that are ready to run (pending + all deps completed).
      final ready = _readyTasks();

      // Assign ready tasks to idle agents.
      for (final task in ready) {
        final agent = _pickAgent(task);
        if (agent == null) break; // No idle agents available.
        await _runTaskOnAgent(task, agent);
      }

      // Work stealing: let idle agents pick up any remaining pending tasks.
      if (_config.enableWorkStealing) {
        _workSteal();
      }

      // If no tasks are running and nothing is ready, we are stuck or done.
      final runningCount =
          _tasks.values.where((t) => t.status == TaskStatus.running).length;
      if (runningCount == 0 && ready.isEmpty) break;

      // Yield to allow running tasks to progress.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    stopwatch.stop();

    // Aggregate results.
    final taskResults = <String, dynamic>{};
    for (final task in _tasks.values) {
      if (task.result != null) {
        taskResults[task.id] = task.result;
      }
    }

    final progress = getProgress();
    return SwarmResult(
      success: progress.failed == 0 && progress.cancelled == 0,
      progress: progress,
      taskResults: taskResults,
      duration: stopwatch.elapsed,
      error: _cancelled ? 'Swarm execution was cancelled.' : null,
    );
  }

  /// Execute a single task on an agent (non-blocking — launches the work
  /// in its own async context).
  Future<void> _runTaskOnAgent(SwarmTask task, SwarmAgent agent) async {
    task.markRunning(agent.id);
    agent.assignTask(task.id);

    final context = AgentContext(
      agent: agent,
      task: task,
      messageBus: _messageBus,
      sharedMemory: _sharedMemory,
    );

    // Schedule the work but don't await in the main loop — we poll for
    // completion via status checks.
    unawaited(_executeWithTimeout(context, task, agent));
  }

  Future<void> _executeWithTimeout(
    AgentContext context,
    SwarmTask task,
    SwarmAgent agent,
  ) async {
    try {
      final result = await _executor(context).timeout(
        Duration(seconds: task.timeoutSeconds),
      );
      if (_cancelled) {
        task.markCancelled();
      } else {
        task.markCompleted(result);
      }
    } on TimeoutException {
      task.markFailed('Task timed out after ${task.timeoutSeconds}s');
    } catch (e) {
      task.markFailed(e.toString());
    } finally {
      agent.completeTask();
    }
  }

  // ---- Work stealing -------------------------------------------------------

  void _workSteal() {
    final idleAgents = _agents.values.where((a) => a.isIdle).toList();
    if (idleAgents.isEmpty) return;

    final pendingTasks = _readyTasks();
    for (final task in pendingTasks) {
      if (idleAgents.isEmpty) break;
      final agent = idleAgents.removeAt(0);
      unawaited(_runTaskOnAgent(task, agent));
    }
  }

  // ---- Helpers -------------------------------------------------------------

  /// Pick an idle agent for [task]. Prefers agents explicitly assigned, then
  /// any idle agent.
  SwarmAgent? _pickAgent(SwarmTask task) {
    // If the task has a pre-assigned agent, use it if idle.
    if (task.assignedAgentId != null) {
      final agent = _agents[task.assignedAgentId!];
      if (agent != null && agent.isIdle) return agent;
    }
    // Otherwise pick any idle agent.
    for (final agent in _agents.values) {
      if (agent.isIdle) return agent;
    }
    return null;
  }

  /// Tasks whose dependencies have all completed.
  List<SwarmTask> _readyTasks() {
    return _tasks.values.where((task) {
      if (task.status != TaskStatus.pending) return false;
      return task.dependencies.every((depId) {
        final dep = _tasks[depId];
        return dep != null && dep.status == TaskStatus.completed;
      });
    }).toList();
  }

  /// Mark tasks as blocked if any dependency has failed or been cancelled.
  void _updateBlockedTasks() {
    for (final task in _tasks.values) {
      if (task.status != TaskStatus.pending) continue;
      final isBlocked = task.dependencies.any((depId) {
        final dep = _tasks[depId];
        if (dep == null) return true;
        return dep.status == TaskStatus.failed ||
            dep.status == TaskStatus.cancelled;
      });
      if (isBlocked) {
        task.markBlocked();
      }
    }
  }

  /// Whether all tasks have reached a terminal state.
  bool _isComplete() {
    return _tasks.values.every((task) =>
        task.status == TaskStatus.completed ||
        task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled ||
        task.status == TaskStatus.blocked);
  }

  // ---- Status & Control ----------------------------------------------------

  /// Get a snapshot of overall swarm progress.
  SwarmProgress getProgress() {
    int completed = 0, failed = 0, running = 0;
    int pending = 0, cancelled = 0, blocked = 0;
    for (final task in _tasks.values) {
      switch (task.status) {
        case TaskStatus.completed:
          completed++;
          break;
        case TaskStatus.failed:
          failed++;
          break;
        case TaskStatus.running:
          running++;
          break;
        case TaskStatus.pending:
          pending++;
          break;
        case TaskStatus.cancelled:
          cancelled++;
          break;
        case TaskStatus.blocked:
          blocked++;
          break;
      }
    }
    return SwarmProgress(
      total: _tasks.length,
      completed: completed,
      failed: failed,
      running: running,
      pending: pending,
      cancelled: cancelled,
      blocked: blocked,
    );
  }

  /// Human-readable status summary.
  String getStatus() {
    final p = getProgress();
    final agentStatus = _agents.values
        .map((a) => '  ${a.name} (${a.role.name}): '
            '${a.isIdle ? "idle" : "running ${a.currentTaskId}"}')
        .join('\n');
    return 'Swarm Status\n'
        '  Tasks: ${p.completed}/${p.total} completed, '
        '${p.failed} failed, ${p.running} running, '
        '${p.pending} pending, ${p.blocked} blocked\n'
        'Agents:\n$agentStatus';
  }

  /// Cancel all running and pending tasks.
  void cancel() {
    _cancelled = true;
    for (final task in _tasks.values) {
      if (task.status == TaskStatus.running ||
          task.status == TaskStatus.pending) {
        task.markCancelled();
      }
    }
    for (final agent in _agents.values) {
      if (!agent.isIdle) {
        agent.releaseTask();
      }
    }
  }

  /// Reset the orchestrator, clearing all agents, tasks and messages.
  void reset() {
    _cancelled = false;
    _agents.clear();
    _tasks.clear();
    _messageBus.clear();
    _sharedMemory.clear();
    _agentCounter = 0;
  }

  // ---- Default executor (stub) ---------------------------------------------

  static Future<dynamic> _defaultExecutor(AgentContext context) async {
    // Simulate some work proportional to description length.
    final workMs = 50 + (context.task.description.length % 200);
    await Future<void>.delayed(Duration(milliseconds: workMs));
    return 'Completed: ${context.task.description}';
  }
}
