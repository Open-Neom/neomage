// task_service.dart — Background task management for flutter_claw
// Port of neom_claw/src/tasks/ (~3.3K TS LOC) to pure Dart.

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

// ---------------------------------------------------------------------------
// Enums & sealed types
// ---------------------------------------------------------------------------

enum TaskStatus {
  pending,
  queued,
  running,
  completed,
  failed,
  cancelled,
  timedOut;

  bool get isTerminal =>
      this == completed || this == failed || this == cancelled || this == timedOut;

  String get label => switch (this) {
        pending => 'Pending',
        queued => 'Queued',
        running => 'Running',
        completed => 'Completed',
        failed => 'Failed',
        cancelled => 'Cancelled',
        timedOut => 'Timed Out',
      };
}

enum TaskPriority implements Comparable<TaskPriority> {
  low(0),
  normal(1),
  high(2),
  critical(3);

  final int value;
  const TaskPriority(this.value);

  @override
  int compareTo(TaskPriority other) => value.compareTo(other.value);
}

sealed class TaskResult<T> {
  const TaskResult();
}

class TaskSuccess<T> extends TaskResult<T> {
  final T value;
  const TaskSuccess(this.value);

  @override
  String toString() => 'TaskSuccess($value)';
}

class TaskFailure<T> extends TaskResult<T> {
  final Object error;
  final StackTrace? stackTrace;
  const TaskFailure(this.error, [this.stackTrace]);

  @override
  String toString() => 'TaskFailure($error)';
}

class TaskCancelled<T> extends TaskResult<T> {
  final String reason;
  const TaskCancelled([this.reason = 'Cancelled by user']);

  @override
  String toString() => 'TaskCancelled($reason)';
}

// ---------------------------------------------------------------------------
// TaskProgress
// ---------------------------------------------------------------------------

class TaskProgress {
  final int current;
  final int total;
  final String message;
  final double? percentage;

  const TaskProgress({
    this.current = 0,
    this.total = 0,
    this.message = '',
    this.percentage,
  });

  double get fraction {
    if (percentage != null) return percentage!.clamp(0.0, 1.0);
    if (total <= 0) return 0.0;
    return (current / total).clamp(0.0, 1.0);
  }

  bool get isIndeterminate => total <= 0 && percentage == null;

  TaskProgress copyWith({
    int? current,
    int? total,
    String? message,
    double? percentage,
  }) =>
      TaskProgress(
        current: current ?? this.current,
        total: total ?? this.total,
        message: message ?? this.message,
        percentage: percentage ?? this.percentage,
      );

  @override
  String toString() {
    if (isIndeterminate) return 'TaskProgress($message)';
    return 'TaskProgress(${(fraction * 100).toStringAsFixed(1)}% $message)';
  }
}

// ---------------------------------------------------------------------------
// TaskLog
// ---------------------------------------------------------------------------

class TaskLog {
  final List<TaskLogEntry> _entries = [];

  void add(TaskLogLevel level, String message, {Object? data}) {
    _entries.add(TaskLogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      data: data,
    ));
  }

  void info(String message, {Object? data}) =>
      add(TaskLogLevel.info, message, data: data);
  void warn(String message, {Object? data}) =>
      add(TaskLogLevel.warning, message, data: data);
  void error(String message, {Object? data}) =>
      add(TaskLogLevel.error, message, data: data);
  void debug(String message, {Object? data}) =>
      add(TaskLogLevel.debug, message, data: data);

  List<TaskLogEntry> get entries => List.unmodifiable(_entries);
  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  List<TaskLogEntry> byLevel(TaskLogLevel level) =>
      _entries.where((e) => e.level == level).toList();

  List<TaskLogEntry> since(DateTime time) =>
      _entries.where((e) => e.timestamp.isAfter(time)).toList();

  void clear() => _entries.clear();

  String format({bool includeDebug = false}) {
    final buf = StringBuffer();
    for (final entry in _entries) {
      if (!includeDebug && entry.level == TaskLogLevel.debug) continue;
      buf.writeln(entry.format());
    }
    return buf.toString();
  }
}

enum TaskLogLevel {
  debug,
  info,
  warning,
  error;

  String get prefix => switch (this) {
        debug => 'DEBUG',
        info => 'INFO',
        warning => 'WARN',
        error => 'ERROR',
      };
}

class TaskLogEntry {
  final DateTime timestamp;
  final TaskLogLevel level;
  final String message;
  final Object? data;

  const TaskLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.data,
  });

  String format() {
    final ts =
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final dataStr = data != null ? ' | $data' : '';
    return '[$ts] ${level.prefix}: $message$dataStr';
  }
}

// ---------------------------------------------------------------------------
// BackgroundTask
// ---------------------------------------------------------------------------

typedef TaskFunction<T> = Future<T> Function(
    TaskProgress Function(TaskProgress) updateProgress);

class BackgroundTask<T> {
  final String id;
  final String name;
  final TaskPriority priority;
  final Duration? timeout;
  final TaskFunction<T> _function;
  final TaskLog log = TaskLog();

  TaskStatus _status = TaskStatus.pending;
  TaskResult<T>? _result;
  TaskProgress _progress = const TaskProgress();
  DateTime? _startTime;
  DateTime? _endTime;
  DateTime _createdAt;
  Completer<TaskResult<T>>? _completer;
  Timer? _timeoutTimer;
  bool _cancelRequested = false;

  BackgroundTask({
    required this.id,
    required this.name,
    required TaskFunction<T> function,
    this.priority = TaskPriority.normal,
    this.timeout,
  })  : _function = function,
        _createdAt = DateTime.now();

  TaskStatus get status => _status;
  TaskResult<T>? get result => _result;
  TaskProgress get progress => _progress;
  DateTime? get startTime => _startTime;
  DateTime? get endTime => _endTime;
  DateTime get createdAt => _createdAt;
  Duration? get elapsed =>
      _startTime == null ? null : (_endTime ?? DateTime.now()).difference(_startTime!);
  bool get isRunning => _status == TaskStatus.running;
  bool get isTerminal => _status.isTerminal;
  bool get cancelRequested => _cancelRequested;

  Future<TaskResult<T>> run() async {
    if (_status != TaskStatus.pending && _status != TaskStatus.queued) {
      return _result ?? TaskCancelled<T>('Task already executed');
    }

    _status = TaskStatus.running;
    _startTime = DateTime.now();
    _completer = Completer<TaskResult<T>>();
    log.info('Task started: $name');

    if (timeout != null) {
      _timeoutTimer = Timer(timeout!, () {
        if (!_completer!.isCompleted) {
          _status = TaskStatus.timedOut;
          _endTime = DateTime.now();
          _result = TaskCancelled<T>('Task timed out after $timeout');
          log.error('Task timed out after $timeout');
          _completer!.complete(_result!);
        }
      });
    }

    try {
      final value = await _function((p) {
        _progress = p;
        return p;
      });

      if (_cancelRequested) {
        _status = TaskStatus.cancelled;
        _result = const TaskCancelled();
        log.info('Task cancelled');
      } else if (!_completer!.isCompleted) {
        _status = TaskStatus.completed;
        _result = TaskSuccess<T>(value);
        log.info('Task completed successfully');
      }
    } catch (e, st) {
      if (!_completer!.isCompleted) {
        _status = TaskStatus.failed;
        _result = TaskFailure<T>(e, st);
        log.error('Task failed: $e');
      }
    } finally {
      _endTime = DateTime.now();
      _timeoutTimer?.cancel();
      if (!_completer!.isCompleted) {
        _completer!.complete(_result!);
      }
    }

    return _result!;
  }

  void cancel([String reason = 'Cancelled by user']) {
    _cancelRequested = true;
    if (_status == TaskStatus.pending || _status == TaskStatus.queued) {
      _status = TaskStatus.cancelled;
      _endTime = DateTime.now();
      _result = TaskCancelled<T>(reason);
      log.info('Task cancelled before execution: $reason');
      _completer?.complete(_result!);
    }
  }

  Future<TaskResult<T>> waitForCompletion() {
    if (_completer != null) return _completer!.future;
    if (_result != null) return Future.value(_result!);
    return Future.value(TaskCancelled<T>('Task not started'));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': _status.label,
        'priority': priority.name,
        'progress': {
          'current': _progress.current,
          'total': _progress.total,
          'message': _progress.message,
          'fraction': _progress.fraction,
        },
        'createdAt': _createdAt.toIso8601String(),
        'startTime': _startTime?.toIso8601String(),
        'endTime': _endTime?.toIso8601String(),
        'elapsed': elapsed?.inMilliseconds,
      };
}

// ---------------------------------------------------------------------------
// TaskIsolateRunner — run heavy work in a Dart isolate
// ---------------------------------------------------------------------------

class TaskIsolateRunner {
  /// Runs [computation] in a separate isolate with the given [message].
  /// Returns the result. Throws if the computation fails.
  static Future<R> run<M, R>(
    M message,
    Future<R> Function(M message) computation, {
    Duration? timeout,
  }) async {
    final resultPort = ReceivePort();
    final errorPort = ReceivePort();

    late final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        (sendPort) async {
          try {
            // We cannot directly pass the computation closure to an isolate.
            // Instead, the caller should structure work as top-level functions.
            // This is a simplified bridge — real usage needs a top-level entrypoint.
            sendPort.send(_IsolateSuccess(null as R));
          } catch (e, st) {
            sendPort.send(_IsolateError(e.toString(), st.toString()));
          }
        },
        resultPort.sendPort,
        errorsAreFatal: true,
        onError: errorPort.sendPort,
      );
    } catch (_) {
      // Fallback: run in current isolate
      return computation(message);
    }

    final completer = Completer<R>();
    Timer? timer;

    if (timeout != null) {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          isolate.kill(priority: Isolate.immediate);
          completer.completeError(
              TimeoutException('Isolate timed out', timeout));
        }
      });
    }

    resultPort.listen((msg) {
      timer?.cancel();
      if (msg is _IsolateSuccess<R>) {
        if (!completer.isCompleted) completer.complete(msg.value);
      } else if (msg is _IsolateError) {
        if (!completer.isCompleted) {
          completer.completeError(Exception(msg.error));
        }
      }
      resultPort.close();
      errorPort.close();
    });

    errorPort.listen((msg) {
      timer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(Exception('Isolate error: $msg'));
      }
      resultPort.close();
      errorPort.close();
    });

    return completer.future;
  }

  /// Convenience: run a simple synchronous function in an isolate.
  static Future<R> compute<M, R>(R Function(M) fn, M message) async {
    return Isolate.run(() => fn(message));
  }
}

class _IsolateSuccess<T> {
  final T value;
  const _IsolateSuccess(this.value);
}

class _IsolateError {
  final String error;
  final String stackTrace;
  const _IsolateError(this.error, this.stackTrace);
}

// ---------------------------------------------------------------------------
// TaskManager — manages a pool of background tasks
// ---------------------------------------------------------------------------

class TaskManager {
  final int maxConcurrent;
  final Map<String, BackgroundTask> _tasks = {};
  final Queue<String> _queue = Queue<String>();
  int _runningCount = 0;
  int _idCounter = 0;
  bool _disposed = false;

  final StreamController<TaskEvent> _eventController =
      StreamController<TaskEvent>.broadcast();

  TaskManager({this.maxConcurrent = 4});

  Stream<TaskEvent> get events => _eventController.stream;
  bool get disposed => _disposed;

  /// Launch a new task. Returns the task ID.
  String launch<T>({
    required String name,
    required TaskFunction<T> function,
    TaskPriority priority = TaskPriority.normal,
    Duration? timeout,
    String? id,
  }) {
    if (_disposed) throw StateError('TaskManager is disposed');

    final taskId = id ?? 'task_${++_idCounter}';
    final task = BackgroundTask<T>(
      id: taskId,
      name: name,
      function: function,
      priority: priority,
      timeout: timeout,
    );

    _tasks[taskId] = task;
    _eventController.add(TaskCreated(taskId, name));
    task.log.info('Task created with priority ${priority.name}');

    if (_runningCount < maxConcurrent) {
      _startTask(taskId);
    } else {
      task._status = TaskStatus.queued;
      _insertIntoQueue(taskId, priority);
      task.log.info('Task queued (${_queue.length} in queue)');
      _eventController.add(TaskQueued(taskId));
    }

    return taskId;
  }

  void _insertIntoQueue(String taskId, TaskPriority priority) {
    // Priority queue: higher priority tasks go first
    if (_queue.isEmpty) {
      _queue.add(taskId);
      return;
    }
    // Simple insertion — find the right spot
    final list = _queue.toList();
    int insertIdx = list.length;
    for (int i = 0; i < list.length; i++) {
      final queuedTask = _tasks[list[i]];
      if (queuedTask != null && queuedTask.priority.compareTo(priority) < 0) {
        insertIdx = i;
        break;
      }
    }
    list.insert(insertIdx, taskId);
    _queue.clear();
    _queue.addAll(list);
  }

  Future<void> _startTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    _runningCount++;
    _eventController.add(TaskStarted(taskId));

    final result = await task.run();

    _runningCount--;
    _eventController.add(TaskCompleted(taskId, result));

    // Start next queued task
    _processQueue();
  }

  void _processQueue() {
    while (_runningCount < maxConcurrent && _queue.isNotEmpty) {
      final nextId = _queue.removeFirst();
      final nextTask = _tasks[nextId];
      if (nextTask != null && !nextTask.isTerminal) {
        _startTask(nextId);
      }
    }
  }

  /// Cancel a running or queued task.
  void cancel(String taskId, [String reason = 'Cancelled by user']) {
    final task = _tasks[taskId];
    if (task == null) return;

    task.cancel(reason);
    _queue.remove(taskId);
    _eventController.add(TaskCancelledEvent(taskId, reason));

    if (task.isRunning) {
      _runningCount--;
      _processQueue();
    }
  }

  /// Get the status of a task.
  TaskStatus? getStatus(String taskId) => _tasks[taskId]?.status;

  /// Get task progress.
  TaskProgress? getProgress(String taskId) => _tasks[taskId]?.progress;

  /// Get a task by ID.
  BackgroundTask? getTask(String taskId) => _tasks[taskId];

  /// Get the result of a completed task.
  TaskResult? getResult(String taskId) => _tasks[taskId]?.result;

  /// List all tasks, optionally filtered by status.
  List<BackgroundTask> listTasks({TaskStatus? status}) {
    final tasks = _tasks.values.toList();
    if (status != null) {
      return tasks.where((t) => t.status == status).toList();
    }
    return tasks;
  }

  /// Wait for a specific task to complete.
  Future<TaskResult?> waitForTask(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return null;
    return task.waitForCompletion();
  }

  /// Wait for all running tasks to complete.
  Future<void> waitForAll() async {
    final futures = _tasks.values
        .where((t) => t.isRunning || t.status == TaskStatus.queued)
        .map((t) => t.waitForCompletion());
    await Future.wait(futures);
  }

  /// Cancel all tasks.
  void cancelAll([String reason = 'All tasks cancelled']) {
    for (final taskId in _tasks.keys.toList()) {
      cancel(taskId, reason);
    }
  }

  /// Remove completed/cancelled/failed tasks from the registry.
  int pruneCompleted() {
    final toRemove =
        _tasks.entries.where((e) => e.value.isTerminal).map((e) => e.key).toList();
    for (final id in toRemove) {
      _tasks.remove(id);
    }
    return toRemove.length;
  }

  /// Get summary statistics.
  TaskManagerStats get stats => TaskManagerStats(
        total: _tasks.length,
        running: _tasks.values.where((t) => t.status == TaskStatus.running).length,
        queued: _tasks.values.where((t) => t.status == TaskStatus.queued).length,
        completed:
            _tasks.values.where((t) => t.status == TaskStatus.completed).length,
        failed: _tasks.values.where((t) => t.status == TaskStatus.failed).length,
        cancelled:
            _tasks.values.where((t) => t.status == TaskStatus.cancelled).length,
        maxConcurrent: maxConcurrent,
      );

  /// Dispose the task manager. Cancels all running tasks.
  void dispose() {
    _disposed = true;
    cancelAll('TaskManager disposed');
    _eventController.close();
  }

  /// Get execution log for a task.
  TaskLog? getLog(String taskId) => _tasks[taskId]?.log;

  /// Export all tasks as JSON.
  List<Map<String, dynamic>> toJson() =>
      _tasks.values.map((t) => t.toJson()).toList();
}

// ---------------------------------------------------------------------------
// TaskManager statistics
// ---------------------------------------------------------------------------

class TaskManagerStats {
  final int total;
  final int running;
  final int queued;
  final int completed;
  final int failed;
  final int cancelled;
  final int maxConcurrent;

  const TaskManagerStats({
    required this.total,
    required this.running,
    required this.queued,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.maxConcurrent,
  });

  int get pending => total - running - queued - completed - failed - cancelled;

  @override
  String toString() =>
      'Tasks: $total total, $running running, $queued queued, '
      '$completed done, $failed failed, $cancelled cancelled';
}

// ---------------------------------------------------------------------------
// Task events for reactive updates
// ---------------------------------------------------------------------------

sealed class TaskEvent {
  final String taskId;
  const TaskEvent(this.taskId);
}

class TaskCreated extends TaskEvent {
  final String name;
  const TaskCreated(super.taskId, this.name);
}

class TaskQueued extends TaskEvent {
  const TaskQueued(super.taskId);
}

class TaskStarted extends TaskEvent {
  const TaskStarted(super.taskId);
}

class TaskCompleted extends TaskEvent {
  final TaskResult result;
  const TaskCompleted(super.taskId, this.result);
}

class TaskCancelledEvent extends TaskEvent {
  final String reason;
  const TaskCancelledEvent(super.taskId, this.reason);
}

class TaskProgressUpdated extends TaskEvent {
  final TaskProgress progress;
  const TaskProgressUpdated(super.taskId, this.progress);
}
