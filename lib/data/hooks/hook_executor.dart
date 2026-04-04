// Hook execution engine — port of neom_claw/src/hooks/executor.ts.
// Manages hook registration, chain execution, built-in hooks,
// execution history, and statistics.

import 'dart:async';

import 'hook_types.dart';

// ---------------------------------------------------------------------------
// Hook Execution Event
// ---------------------------------------------------------------------------

/// Record of a single hook execution, used for history and diagnostics.
class HookExecutionEvent {
  /// ID of the hook that was executed.
  final String hookId;

  /// Name of the hook.
  final String hookName;

  /// Type of hook that was executed.
  final HookType type;

  /// The context that was passed to the hook.
  final HookContext context;

  /// The result returned by the hook.
  final HookResult result;

  /// How long the hook took to execute.
  final Duration duration;

  /// Error that occurred during execution, if any.
  final Object? error;

  /// Stack trace for the error, if any.
  final StackTrace? errorStackTrace;

  /// When this event was recorded.
  final DateTime timestamp;

  const HookExecutionEvent({
    required this.hookId,
    required this.hookName,
    required this.type,
    required this.context,
    required this.result,
    required this.duration,
    this.error,
    this.errorStackTrace,
    required this.timestamp,
  });

  /// Whether this execution resulted in an error.
  bool get hasError => error != null;

  /// Whether the hook aborted the chain.
  bool get wasAborted => result is HookAbort;
}

// ---------------------------------------------------------------------------
// Hook Statistics
// ---------------------------------------------------------------------------

/// Aggregate statistics about hook executions.
class HookStats {
  /// Total number of hook executions across all types.
  final int totalExecutions;

  /// Execution count broken down by hook type.
  final Map<HookType, int> executionsByType;

  /// Average execution duration across all hooks.
  final Duration avgDuration;

  /// Total number of failed executions (exceptions thrown).
  final int failureCount;

  /// Total number of aborted chains.
  final int abortCount;

  /// Timestamp of the most recent execution.
  final DateTime? lastExecution;

  /// Execution count broken down by individual hook ID.
  final Map<String, int> executionsByHookId;

  const HookStats({
    required this.totalExecutions,
    required this.executionsByType,
    required this.avgDuration,
    required this.failureCount,
    required this.abortCount,
    this.lastExecution,
    this.executionsByHookId = const {},
  });

  /// Empty stats for initialization.
  factory HookStats.empty() => const HookStats(
    totalExecutions: 0,
    executionsByType: {},
    avgDuration: Duration.zero,
    failureCount: 0,
    abortCount: 0,
  );

  /// Failure rate as a percentage (0.0 to 1.0).
  double get failureRate =>
      totalExecutions == 0 ? 0.0 : failureCount / totalExecutions;
}

// ---------------------------------------------------------------------------
// Hook Chain Runner (Internal)
// ---------------------------------------------------------------------------

/// Internal class that executes a chain of hooks in priority order.
///
/// Handles the flow-control semantics of each [HookResult] variant:
/// - [HookContinue]: proceed to next hook, optionally with modified data
/// - [HookSkip]: skip to next hook without modification
/// - [HookAbort]: stop the entire chain immediately
/// - [HookRetry]: re-execute the current hook after a delay
/// - [HookTransform]: replace data and continue to next hook
class _HookChainRunner {
  /// Default timeout per individual hook execution.
  static const _defaultHookTimeout = Duration(seconds: 5);

  /// Maximum retry attempts for a single hook.
  static const _maxRetryAttempts = 3;

  /// Run a chain of hooks in priority order, returning the final result.
  ///
  /// The [context] is passed to each hook. If a hook returns a [HookTransform]
  /// or [HookContinue] with modified data, the context metadata is updated
  /// for subsequent hooks.
  ///
  /// The [onEvent] callback is invoked after each hook execution for logging.
  static Future<HookResult> run({
    required List<HookRegistration> hooks,
    required HookContext context,
    Duration? timeout,
    void Function(HookExecutionEvent)? onEvent,
  }) async {
    final hookTimeout = timeout ?? _defaultHookTimeout;
    var currentContext = context;
    HookResult lastResult = const HookContinue();

    for (final hook in hooks) {
      // Check matcher
      if (hook.matcher != null && !hook.matcher!(currentContext)) {
        continue;
      }

      // Execute with retry support
      final eventResult = await _executeWithRetry(
        hook: hook,
        context: currentContext,
        timeout: hookTimeout,
      );

      // Record the event
      if (onEvent != null) {
        onEvent(eventResult.event);
      }

      final result = eventResult.result;
      lastResult = result;

      // Handle the result
      switch (result) {
        case HookContinue(:final modifiedData):
          if (modifiedData != null) {
            currentContext = currentContext.copyWith(
              metadata: {...currentContext.metadata, ...modifiedData},
              previousResults: [...currentContext.previousResults, result],
            );
          } else {
            currentContext = currentContext.copyWith(
              previousResults: [...currentContext.previousResults, result],
            );
          }

        case HookSkip():
          currentContext = currentContext.copyWith(
            previousResults: [...currentContext.previousResults, result],
          );
          continue;

        case HookAbort():
          return result;

        case HookRetry():
          // Retry is handled inside _executeWithRetry; if we get here,
          // all retries were exhausted and the last result was Retry.
          // Treat as continue.
          currentContext = currentContext.copyWith(
            previousResults: [...currentContext.previousResults, result],
          );

        case HookTransform(:final data):
          currentContext = currentContext.copyWith(
            metadata: {...currentContext.metadata, ...data},
            previousResults: [...currentContext.previousResults, result],
          );
      }
    }

    return lastResult;
  }

  /// Execute a single hook with retry logic.
  static Future<_ExecutionResult> _executeWithRetry({
    required HookRegistration hook,
    required HookContext context,
    required Duration timeout,
  }) async {
    var attempt = 0;
    HookResult result = const HookContinue();
    Object? lastError;
    StackTrace? lastStackTrace;

    while (attempt <= _maxRetryAttempts) {
      final stopwatch = Stopwatch()..start();

      try {
        result = await hook.execute(context).timeout(timeout);
        stopwatch.stop();

        final event = HookExecutionEvent(
          hookId: hook.id,
          hookName: hook.name,
          type: hook.type,
          context: context,
          result: result,
          duration: stopwatch.elapsed,
          timestamp: DateTime.now(),
        );

        if (result is HookRetry) {
          final retry = result;
          if (attempt < retry.maxAttempts && attempt < _maxRetryAttempts) {
            await Future<void>.delayed(retry.delay);
            attempt++;
            continue;
          }
          // Max retries exhausted — return as-is
          return _ExecutionResult(result: result, event: event);
        }

        return _ExecutionResult(result: result, event: event);
      } on TimeoutException {
        stopwatch.stop();
        lastError = TimeoutException(
          'Hook "${hook.name}" timed out after $timeout',
          timeout,
        );
        lastStackTrace = StackTrace.current;

        final event = HookExecutionEvent(
          hookId: hook.id,
          hookName: hook.name,
          type: hook.type,
          context: context,
          result: HookAbort('Hook timed out', error: lastError),
          duration: stopwatch.elapsed,
          error: lastError,
          errorStackTrace: lastStackTrace,
          timestamp: DateTime.now(),
        );

        // Timeout is not retried — return error immediately
        return _ExecutionResult(result: const HookContinue(), event: event);
      } catch (e, st) {
        stopwatch.stop();
        lastError = e;
        lastStackTrace = st;

        final event = HookExecutionEvent(
          hookId: hook.id,
          hookName: hook.name,
          type: hook.type,
          context: context,
          result: const HookContinue(),
          duration: stopwatch.elapsed,
          error: e,
          errorStackTrace: st,
          timestamp: DateTime.now(),
        );

        // Exceptions in individual hooks should not break the chain.
        // Log and continue.
        return _ExecutionResult(result: const HookContinue(), event: event);
      }
    }

    // Should not reach here, but return continue as safety fallback.
    return _ExecutionResult(
      result: result,
      event: HookExecutionEvent(
        hookId: hook.id,
        hookName: hook.name,
        type: hook.type,
        context: context,
        result: result,
        duration: Duration.zero,
        error: lastError,
        errorStackTrace: lastStackTrace,
        timestamp: DateTime.now(),
      ),
    );
  }
}

/// Internal result wrapper for chain execution.
class _ExecutionResult {
  final HookResult result;
  final HookExecutionEvent event;

  const _ExecutionResult({required this.result, required this.event});
}

// ---------------------------------------------------------------------------
// Hook Executor
// ---------------------------------------------------------------------------

/// Central hook execution engine.
///
/// Manages hook registration, chain execution, history tracking, and
/// statistics. All hook execution flows through this class.
///
/// Usage:
/// ```dart
/// final executor = HookExecutor();
///
/// // Register a hook
/// executor.register(HookRegistration(
///   id: 'my-hook',
///   type: HookType.preToolExecution,
///   name: 'My Hook',
///   handler: (ctx) => const HookContinue(),
/// ));
///
/// // Execute hooks for a type
/// final result = await executor.executeAsync(
///   HookType.preToolExecution,
///   ToolHookContext(
///     hookType: HookType.preToolExecution,
///     timestamp: DateTime.now(),
///     toolName: 'bash',
///     toolInput: {'command': 'ls'},
///   ),
/// );
/// ```
class HookExecutor {
  /// Hook chains indexed by hook type.
  final Map<HookType, HookChain> _chains = {};

  /// Flat index of all registrations by ID for O(1) lookup.
  final Map<String, HookRegistration> _registrationsById = {};

  /// Execution history, newest first.
  final List<HookExecutionEvent> _history = [];

  /// Maximum number of history entries to keep.
  final int maxHistorySize;

  /// Stream controller for hook execution events.
  final StreamController<HookExecutionEvent> _eventController =
      StreamController<HookExecutionEvent>.broadcast();

  /// Running statistics.
  int _totalExecutions = 0;
  int _failureCount = 0;
  int _abortCount = 0;
  int _totalDurationMicros = 0;
  DateTime? _lastExecution;
  final Map<HookType, int> _executionsByType = {};
  final Map<String, int> _executionsByHookId = {};

  /// Default timeout for individual hook execution.
  final Duration defaultTimeout;

  HookExecutor({
    this.maxHistorySize = 1000,
    this.defaultTimeout = const Duration(seconds: 5),
  });

  // ── Registration ──

  /// Register a hook and return its ID.
  ///
  /// The hook is added to the chain for its [HookRegistration.type] and
  /// sorted by priority.
  String register(HookRegistration registration) {
    if (_registrationsById.containsKey(registration.id)) {
      throw StateError(
        'Hook with id "${registration.id}" is already registered. '
        'Unregister it first or use a different id.',
      );
    }

    final chain = _chains.putIfAbsent(
      registration.type,
      () => HookChain(type: registration.type),
    );
    chain.add(registration);
    _registrationsById[registration.id] = registration;

    return registration.id;
  }

  /// Unregister a hook by ID. Returns true if found and removed.
  bool unregister(String hookId) {
    final registration = _registrationsById.remove(hookId);
    if (registration == null) return false;

    final chain = _chains[registration.type];
    chain?.remove(hookId);
    return true;
  }

  /// Enable a previously disabled hook.
  void enable(String hookId) {
    final registration = _registrationsById[hookId];
    if (registration == null) {
      throw ArgumentError('No hook registered with id "$hookId"');
    }
    registration.enabled = true;
  }

  /// Disable a hook without unregistering it.
  void disable(String hookId) {
    final registration = _registrationsById[hookId];
    if (registration == null) {
      throw ArgumentError('No hook registered with id "$hookId"');
    }
    registration.enabled = false;
  }

  /// Get all registered hooks, optionally filtered by type and/or priority.
  List<HookRegistration> getRegistered({
    HookType? type,
    HookPriority? priority,
  }) {
    Iterable<HookRegistration> results = _registrationsById.values;

    if (type != null) {
      results = results.where((r) => r.type == type);
    }
    if (priority != null) {
      results = results.where((r) => r.priority == priority);
    }

    final list = results.toList()
      ..sort((a, b) => a.priority.value.compareTo(b.priority.value));
    return list;
  }

  /// Check if any hooks are registered for a given type.
  bool hasHooks(HookType type) {
    final chain = _chains[type];
    return chain != null && chain.activeLength > 0;
  }

  /// Unregister all hooks from a given source.
  int unregisterSource(String source) {
    var removed = 0;
    for (final chain in _chains.values) {
      removed += chain.removeBySource(source);
    }
    _registrationsById.removeWhere((_, r) => r.source == source);
    return removed;
  }

  /// Remove all registered hooks.
  void clearAll() {
    _chains.clear();
    _registrationsById.clear();
  }

  // ── Execution ──

  /// Execute all matching hooks for the given type synchronously.
  ///
  /// This is a convenience wrapper around [executeAsync] for callers in
  /// synchronous contexts. Internally still async.
  HookResult execute(HookType type, HookContext context) {
    // For truly sync execution, we run hooks that have sync handlers only.
    final chain = _chains[type];
    if (chain == null || chain.isEmpty) return const HookContinue();

    final hooks = chain.activeRegistrations;
    if (hooks.isEmpty) return const HookContinue();

    HookResult lastResult = const HookContinue();

    for (final hook in hooks) {
      if (hook.isAsync) continue; // Skip async hooks in sync execution
      if (hook.matcher != null && !hook.matcher!(context)) continue;

      final stopwatch = Stopwatch()..start();
      try {
        lastResult = hook.handler!(context);
        stopwatch.stop();
        _recordEvent(
          HookExecutionEvent(
            hookId: hook.id,
            hookName: hook.name,
            type: type,
            context: context,
            result: lastResult,
            duration: stopwatch.elapsed,
            timestamp: DateTime.now(),
          ),
        );

        if (lastResult is HookAbort) return lastResult;
      } catch (e, st) {
        stopwatch.stop();
        _recordEvent(
          HookExecutionEvent(
            hookId: hook.id,
            hookName: hook.name,
            type: type,
            context: context,
            result: const HookContinue(),
            duration: stopwatch.elapsed,
            error: e,
            errorStackTrace: st,
            timestamp: DateTime.now(),
          ),
        );
      }
    }

    return lastResult;
  }

  /// Execute all matching hooks for the given type asynchronously.
  ///
  /// Runs the hook chain in priority order. Returns the final [HookResult].
  Future<HookResult> executeAsync(HookType type, HookContext context) async {
    final chain = _chains[type];
    if (chain == null || chain.isEmpty) return const HookContinue();

    final hooks = chain.activeRegistrations;
    if (hooks.isEmpty) return const HookContinue();

    return _HookChainRunner.run(
      hooks: hooks,
      context: context,
      timeout: defaultTimeout,
      onEvent: _recordEvent,
    );
  }

  /// Execute hooks for a batch of contexts, returning one result per context.
  ///
  /// Each context is processed independently through the full hook chain.
  Future<List<HookResult>> executeBatch(
    HookType type,
    List<HookContext> contexts,
  ) async {
    final results = <HookResult>[];
    for (final context in contexts) {
      results.add(await executeAsync(type, context));
    }
    return results;
  }

  /// Execute hooks with an overall timeout for the entire chain.
  ///
  /// If the timeout is exceeded, returns [HookAbort] with a timeout message.
  Future<HookResult> executeWithTimeout(
    HookType type,
    HookContext context,
    Duration timeout,
  ) async {
    try {
      return await executeAsync(type, context).timeout(timeout);
    } on TimeoutException {
      return HookAbort(
        'Hook chain for $type timed out after $timeout',
        error: TimeoutException('Chain timeout', timeout),
      );
    }
  }

  // ── Event Stream ──

  /// Stream of hook execution events. Subscribe to monitor all hook activity.
  Stream<HookExecutionEvent> get onHookExecuted => _eventController.stream;

  // ── History ──

  /// Get execution history, optionally filtered by type and/or limited.
  List<HookExecutionEvent> getExecutionHistory({HookType? type, int? limit}) {
    Iterable<HookExecutionEvent> results = _history;

    if (type != null) {
      results = results.where((e) => e.type == type);
    }

    final list = results.toList();
    if (limit != null && list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  /// Clear all execution history and reset statistics.
  void clearHistory() {
    _history.clear();
    _totalExecutions = 0;
    _failureCount = 0;
    _abortCount = 0;
    _totalDurationMicros = 0;
    _lastExecution = null;
    _executionsByType.clear();
    _executionsByHookId.clear();
  }

  // ── Statistics ──

  /// Get aggregate execution statistics.
  HookStats stats() {
    return HookStats(
      totalExecutions: _totalExecutions,
      executionsByType: Map.unmodifiable(_executionsByType),
      avgDuration: _totalExecutions == 0
          ? Duration.zero
          : Duration(microseconds: _totalDurationMicros ~/ _totalExecutions),
      failureCount: _failureCount,
      abortCount: _abortCount,
      lastExecution: _lastExecution,
      executionsByHookId: Map.unmodifiable(_executionsByHookId),
    );
  }

  // ── Disposal ──

  /// Dispose of the executor, closing the event stream.
  void dispose() {
    _eventController.close();
  }

  // ── Private ──

  /// Record an execution event in history and update stats.
  void _recordEvent(HookExecutionEvent event) {
    // History
    _history.insert(0, event);
    if (_history.length > maxHistorySize) {
      _history.removeRange(maxHistorySize, _history.length);
    }

    // Stats
    _totalExecutions++;
    _totalDurationMicros += event.duration.inMicroseconds;
    _lastExecution = event.timestamp;
    _executionsByType[event.type] = (_executionsByType[event.type] ?? 0) + 1;
    _executionsByHookId[event.hookId] =
        (_executionsByHookId[event.hookId] ?? 0) + 1;

    if (event.hasError) _failureCount++;
    if (event.wasAborted) _abortCount++;

    // Broadcast
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }
}

// ---------------------------------------------------------------------------
// Built-in Hooks
// ---------------------------------------------------------------------------

/// Collection of pre-built hooks that implement common safety, auditing,
/// and operational concerns.
///
/// These hooks are designed to be registered with a [HookExecutor] during
/// application initialization. Each method returns a [HookRegistration]
/// that can be customized before registration.
class BuiltInHooks {
  BuiltInHooks._();

  /// Hook that checks permission rules before tool execution.
  ///
  /// Returns [HookAbort] if the tool is not permitted, [HookContinue]
  /// otherwise. Runs at [HookPriority.critical].
  static HookRegistration permissionCheckHook({
    required bool Function(String toolName, Map<String, dynamic> input)
    isPermitted,
  }) {
    return HookRegistration(
      id: 'builtin:permission-check',
      type: HookType.preToolExecution,
      priority: HookPriority.critical,
      name: 'Permission Check',
      description: 'Checks permission rules before tool execution.',
      source: 'builtin',
      tags: {'security', 'permission'},
      handler: (context) {
        if (context is! ToolHookContext) return const HookContinue();
        final permitted = isPermitted(context.toolName, context.toolInput);
        if (!permitted) {
          return HookAbort('Permission denied for tool "${context.toolName}"');
        }
        return const HookContinue();
      },
    );
  }

  /// Hook that enforces sandbox restrictions on file and shell operations.
  ///
  /// Prevents access to paths outside the allowed sandbox. Runs at
  /// [HookPriority.critical].
  static HookRegistration sandboxEnforcementHook({
    required List<String> allowedPaths,
    required bool Function(String path) isInSandbox,
  }) {
    return HookRegistration(
      id: 'builtin:sandbox-enforcement',
      type: HookType.preToolExecution,
      priority: HookPriority.critical,
      name: 'Sandbox Enforcement',
      description: 'Ensures operations stay within the sandbox.',
      source: 'builtin',
      tags: {'security', 'sandbox'},
      handler: (context) {
        if (context is! ToolHookContext) return const HookContinue();

        // Check file paths in tool input
        final path =
            context.toolInput['file_path'] as String? ??
            context.toolInput['path'] as String?;
        if (path != null && !isInSandbox(path)) {
          return HookAbort(
            'Path "$path" is outside the sandbox. '
            'Allowed paths: ${allowedPaths.join(", ")}',
          );
        }
        return const HookContinue();
      },
    );
  }

  /// Hook that enforces rate limits on API calls.
  ///
  /// Tracks call counts per time window and returns [HookRetry] when
  /// the limit is exceeded.
  static HookRegistration rateLimitHook({required int maxCallsPerMinute}) {
    final callTimestamps = <DateTime>[];

    return HookRegistration(
      id: 'builtin:rate-limit',
      type: HookType.preApiCall,
      priority: HookPriority.high,
      name: 'Rate Limit',
      description: 'Enforces rate limits on API calls.',
      source: 'builtin',
      tags: {'safety', 'rate-limit'},
      handler: (context) {
        final now = DateTime.now();
        final windowStart = now.subtract(const Duration(minutes: 1));

        // Clean old entries
        callTimestamps.removeWhere((t) => t.isBefore(windowStart));

        if (callTimestamps.length >= maxCallsPerMinute) {
          final oldestInWindow = callTimestamps.first;
          final waitTime = oldestInWindow
              .add(const Duration(minutes: 1))
              .difference(now);
          return HookRetry(
            waitTime.isNegative ? const Duration(seconds: 1) : waitTime,
          );
        }

        callTimestamps.add(now);
        return const HookContinue();
      },
    );
  }

  /// Hook that logs all tool operations for audit trail.
  ///
  /// Runs at [HookPriority.monitor] so it does not affect control flow.
  static HookRegistration auditLogHook({
    required void Function(String entry) logEntry,
  }) {
    return HookRegistration(
      id: 'builtin:audit-log',
      type: HookType.postToolExecution,
      priority: HookPriority.monitor,
      name: 'Audit Log',
      description: 'Logs all tool operations for audit trail.',
      source: 'builtin',
      tags: {'audit', 'logging'},
      handler: (context) {
        if (context is ToolHookContext) {
          final entry =
              '[${context.timestamp.toIso8601String()}] '
              'Tool: ${context.toolName}, '
              'Session: ${context.sessionId ?? "none"}, '
              'Error: ${context.toolIsError ?? false}';
          logEntry(entry);
        }
        return const HookContinue();
      },
    );
  }

  /// Hook that tracks token usage and estimated cost.
  ///
  /// Accumulates token counts from API responses and provides running totals
  /// via the hook context metadata.
  static HookRegistration costTrackingHook({
    required void Function(int inputTokens, int outputTokens, double cost)
    onUsage,
    double costPerInputToken = 0.000003,
    double costPerOutputToken = 0.000015,
  }) {
    var totalInputTokens = 0;
    var totalOutputTokens = 0;
    var totalCost = 0.0;

    return HookRegistration(
      id: 'builtin:cost-tracking',
      type: HookType.postApiCall,
      priority: HookPriority.monitor,
      name: 'Cost Tracking',
      description: 'Tracks token usage and estimated cost.',
      source: 'builtin',
      tags: {'analytics', 'cost'},
      handler: (context) {
        if (context is ApiHookContext && context.tokenUsage != null) {
          final usage = context.tokenUsage!;
          totalInputTokens += usage.inputTokens;
          totalOutputTokens += usage.outputTokens;
          final callCost =
              (usage.inputTokens * costPerInputToken) +
              (usage.outputTokens * costPerOutputToken);
          totalCost += callCost;
          onUsage(usage.inputTokens, usage.outputTokens, callCost);
        }
        return HookContinue(
          modifiedData: {
            'totalInputTokens': totalInputTokens,
            'totalOutputTokens': totalOutputTokens,
            'totalCost': totalCost,
          },
        );
      },
    );
  }

  /// Hook that creates backup files before modifications.
  ///
  /// Writes a `.bak` file alongside the original before any write or
  /// delete operation.
  static HookRegistration fileBackupHook({
    required Future<void> Function(String path, String content) writeBackup,
  }) {
    return HookRegistration(
      id: 'builtin:file-backup',
      type: HookType.onFileChange,
      priority: HookPriority.high,
      name: 'File Backup',
      description: 'Creates .bak files before modifications.',
      source: 'builtin',
      tags: {'safety', 'backup'},
      asyncHandler: (context) async {
        if (context is FileHookContext) {
          final op = context.operation;
          if (op == FileOperation.write || op == FileOperation.delete) {
            if (context.previousContent != null) {
              await writeBackup(
                '${context.path}.bak',
                context.previousContent!,
              );
            }
          }
        }
        return const HookContinue();
      },
    );
  }

  /// Hook that prevents dangerous git operations.
  ///
  /// Blocks force pushes to protected branches, hard resets, and other
  /// destructive operations.
  static HookRegistration gitSafetyHook({
    List<String> protectedBranches = const ['main', 'master'],
  }) {
    return HookRegistration(
      id: 'builtin:git-safety',
      type: HookType.onGitOperation,
      priority: HookPriority.critical,
      name: 'Git Safety',
      description: 'Prevents dangerous git operations.',
      source: 'builtin',
      tags: {'security', 'git'},
      handler: (context) {
        if (context is! GitHookContext) return const HookContinue();

        // Block force push to protected branches
        if (context.operation == GitOperation.push &&
            context.force &&
            protectedBranches.contains(context.branch)) {
          return HookAbort(
            'Force push to protected branch "${context.branch}" is blocked.',
          );
        }

        // Block hard reset
        if (context.operation == GitOperation.reset &&
            context.metadata['hard'] == true) {
          return HookAbort(
            'Hard reset is blocked. Use soft or mixed reset instead.',
          );
        }

        // Block branch deletion of protected branches
        if (context.operation == GitOperation.branch &&
            context.metadata['delete'] == true &&
            protectedBranches.contains(context.targetBranch)) {
          return HookAbort(
            'Deletion of protected branch "${context.targetBranch}" is blocked.',
          );
        }

        return const HookContinue();
      },
    );
  }

  /// Hook that scans content for potential secrets and sensitive data.
  ///
  /// Checks tool inputs and outputs for patterns that look like API keys,
  /// passwords, tokens, and other secrets.
  static HookRegistration secretDetectionHook({
    void Function(String warning)? onWarning,
  }) {
    // Common patterns for secrets
    final secretPatterns = [
      RegExp(r'(?:api[_-]?key|apikey)\s*[=:]\s*\S+', caseSensitive: false),
      RegExp(r'(?:password|passwd|pwd)\s*[=:]\s*\S+', caseSensitive: false),
      RegExp(r'(?:secret|token)\s*[=:]\s*\S+', caseSensitive: false),
      RegExp(
        r'(?:access[_-]?key|aws[_-]?key)\s*[=:]\s*\S+',
        caseSensitive: false,
      ),
      RegExp(r'-----BEGIN (?:RSA |DSA |EC )?PRIVATE KEY-----'),
      RegExp(r'sk-[a-zA-Z0-9]{20,}'), // OpenAI-style keys
      RegExp(r'ghp_[a-zA-Z0-9]{36}'), // GitHub personal access tokens
      RegExp(r'(?:Bearer|Basic)\s+[a-zA-Z0-9+/=._-]{20,}'),
    ];

    return HookRegistration(
      id: 'builtin:secret-detection',
      type: HookType.preToolExecution,
      priority: HookPriority.high,
      name: 'Secret Detection',
      description: 'Warns about potential secrets in content.',
      source: 'builtin',
      tags: {'security', 'secrets'},
      handler: (context) {
        if (context is! ToolHookContext) return const HookContinue();

        final inputStr = context.toolInput.toString();

        for (final pattern in secretPatterns) {
          if (pattern.hasMatch(inputStr)) {
            final warning =
                'Potential secret detected in tool input for '
                '"${context.toolName}". Pattern: ${pattern.pattern}';
            onWarning?.call(warning);
            return HookContinue(modifiedData: {'secretWarning': warning});
          }
        }

        return const HookContinue();
      },
    );
  }

  /// Register all built-in hooks with the given executor.
  ///
  /// This is a convenience method for initialization. The [config] map
  /// allows customization of individual hooks.
  static void registerAll(
    HookExecutor executor, {
    bool Function(String, Map<String, dynamic>)? isPermitted,
    bool Function(String)? isInSandbox,
    List<String>? allowedPaths,
    int maxCallsPerMinute = 60,
    void Function(String)? logEntry,
    void Function(int, int, double)? onUsage,
    Future<void> Function(String, String)? writeBackup,
    List<String>? protectedBranches,
    void Function(String)? onSecretWarning,
  }) {
    if (isPermitted != null) {
      executor.register(permissionCheckHook(isPermitted: isPermitted));
    }

    if (isInSandbox != null) {
      executor.register(
        sandboxEnforcementHook(
          allowedPaths: allowedPaths ?? [],
          isInSandbox: isInSandbox,
        ),
      );
    }

    executor.register(rateLimitHook(maxCallsPerMinute: maxCallsPerMinute));

    if (logEntry != null) {
      executor.register(auditLogHook(logEntry: logEntry));
    }

    if (onUsage != null) {
      executor.register(costTrackingHook(onUsage: onUsage));
    }

    if (writeBackup != null) {
      executor.register(fileBackupHook(writeBackup: writeBackup));
    }

    executor.register(
      gitSafetyHook(protectedBranches: protectedBranches ?? ['main', 'master']),
    );

    executor.register(secretDetectionHook(onWarning: onSecretWarning));
  }
}
