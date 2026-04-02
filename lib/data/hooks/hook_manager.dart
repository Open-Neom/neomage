// Hook manager — port of openclaude/src/hooks.
// Manages hook registration, matching, and execution lifecycle.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Hook event types.
enum HookEvent {
  preToolUse,
  postToolUse,
  postToolUseFailure,
  permissionDenied,
  userPromptSubmit,
  sessionStart,
  sessionEnd,
  stop,
  preCompact,
  postCompact,
  notification,
}

/// Hook command types.
sealed class HookCommand {
  final String? condition;
  final int? timeoutSeconds;
  final bool async_;
  final bool once;

  const HookCommand({
    this.condition,
    this.timeoutSeconds,
    this.async_ = false,
    this.once = false,
  });
}

/// Shell command hook.
class CommandHook extends HookCommand {
  final String command;
  final String? shell;

  const CommandHook({
    required this.command,
    this.shell,
    super.condition,
    super.timeoutSeconds,
    super.async_,
    super.once,
  });
}

/// Prompt hook — sends prompt to LLM.
class PromptHook extends HookCommand {
  final String prompt;
  final String? model;

  const PromptHook({
    required this.prompt,
    this.model,
    super.condition,
    super.timeoutSeconds,
    super.async_,
    super.once,
  });
}

/// HTTP hook — makes HTTP request.
class HttpHook extends HookCommand {
  final String url;
  final Map<String, String> headers;

  const HttpHook({
    required this.url,
    this.headers = const {},
    super.condition,
    super.timeoutSeconds,
    super.async_,
    super.once,
  });
}

/// Function hook — in-process callback.
class FunctionHook extends HookCommand {
  final Future<bool> Function(Map<String, dynamic> input) callback;
  final String errorMessage;

  FunctionHook({
    required this.callback,
    required this.errorMessage,
    super.condition,
    super.timeoutSeconds,
  });
}

/// A hook matcher — conditions + commands.
class HookMatcher {
  final String? matcher;
  final List<HookCommand> hooks;
  final String? source;

  const HookMatcher({
    this.matcher,
    required this.hooks,
    this.source,
  });
}

/// Result of hook execution.
class HookResult {
  final bool shouldContinue;
  final String? output;
  final String? stopReason;
  final String? systemMessage;

  const HookResult({
    this.shouldContinue = true,
    this.output,
    this.stopReason,
    this.systemMessage,
  });

  factory HookResult.block(String reason) => HookResult(
        shouldContinue: false,
        stopReason: reason,
      );

  factory HookResult.pass([String? output]) => HookResult(output: output);
}

/// Hook manager — registers and executes hooks.
class HookManager {
  final Map<HookEvent, List<HookMatcher>> _hooks = {};
  final List<String> _executedOnceIds = [];

  /// Register a hook matcher for an event.
  void register(HookEvent event, HookMatcher matcher) {
    _hooks.putIfAbsent(event, () => []).add(matcher);
  }

  /// Register multiple matchers.
  void registerAll(Map<HookEvent, List<HookMatcher>> hooks) {
    for (final entry in hooks.entries) {
      for (final matcher in entry.value) {
        register(entry.key, matcher);
      }
    }
  }

  /// Unregister all hooks from a source.
  void unregisterSource(String source) {
    for (final event in _hooks.keys) {
      _hooks[event]!.removeWhere((m) => m.source == source);
    }
  }

  /// Clear all hooks.
  void clear() {
    _hooks.clear();
    _executedOnceIds.clear();
  }

  /// Execute all matching hooks for an event.
  Future<HookResult> executeHooks({
    required HookEvent event,
    Map<String, dynamic> input = const {},
  }) async {
    final matchers = _hooks[event] ?? [];

    for (final matcher in matchers) {
      // Check matcher condition
      if (matcher.matcher != null && matcher.matcher!.isNotEmpty) {
        if (!_matchesCondition(matcher.matcher!, input)) continue;
      }

      for (final hook in matcher.hooks) {
        // Check if condition
        if (hook.condition != null) {
          if (!_evaluateCondition(hook.condition!, input)) continue;
        }

        // Check once
        final hookId = '${event.name}_${hook.hashCode}';
        if (hook.once && _executedOnceIds.contains(hookId)) continue;

        // Execute
        final result = await _executeHook(hook, input);
        if (hook.once) _executedOnceIds.add(hookId);

        if (!result.shouldContinue) return result;
      }
    }

    return const HookResult();
  }

  /// Check if any hooks are registered for an event.
  bool hasHooks(HookEvent event) =>
      _hooks.containsKey(event) && _hooks[event]!.isNotEmpty;

  // ── Private ──

  Future<HookResult> _executeHook(
    HookCommand hook,
    Map<String, dynamic> input,
  ) async {
    final timeout = Duration(seconds: hook.timeoutSeconds ?? 30);

    try {
      return await switch (hook) {
        CommandHook() => _executeCommand(hook, input, timeout),
        PromptHook() => HookResult.pass(), // Needs LLM — placeholder
        HttpHook() => _executeHttp(hook, input, timeout),
        FunctionHook() => _executeFunction(hook, input, timeout),
      };
    } catch (e) {
      return HookResult(output: 'Hook error: $e');
    }
  }

  Future<HookResult> _executeCommand(
    CommandHook hook,
    Map<String, dynamic> input,
    Duration timeout,
  ) async {
    final shell = hook.shell ?? 'bash';
    final env = <String, String>{
      'HOOK_INPUT': jsonEncode(input),
    };

    final result = await Process.run(
      shell,
      ['-c', hook.command],
      environment: env,
    ).timeout(timeout);

    final exitCode = result.exitCode;
    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String).trim();

    if (exitCode == 2) {
      return HookResult.block(stderr.isNotEmpty ? stderr : 'Blocked by hook');
    }

    if (exitCode != 0) {
      return HookResult(output: stderr.isNotEmpty ? stderr : null);
    }

    return HookResult.pass(stdout.isNotEmpty ? stdout : null);
  }

  Future<HookResult> _executeHttp(
    HttpHook hook,
    Map<String, dynamic> input,
    Duration timeout,
  ) async {
    // Placeholder — would use http package
    return const HookResult();
  }

  Future<HookResult> _executeFunction(
    FunctionHook hook,
    Map<String, dynamic> input,
    Duration timeout,
  ) async {
    final passed = await hook.callback(input).timeout(timeout);
    if (!passed) {
      return HookResult.block(hook.errorMessage);
    }
    return const HookResult();
  }

  bool _matchesCondition(String matcher, Map<String, dynamic> input) {
    final toolName = input['tool_name'] as String?;
    if (toolName == null) return true;
    return matcher.isEmpty || matcher == toolName;
  }

  bool _evaluateCondition(String condition, Map<String, dynamic> input) {
    // Simple condition evaluation — tool name match
    if (condition.contains('(')) {
      final parts = condition.split('(');
      final toolName = parts[0].trim();
      final inputToolName = input['tool_name'] as String?;
      return inputToolName == toolName;
    }
    return true;
  }
}
