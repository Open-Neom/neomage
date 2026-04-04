// Hook system types — ported from NeomClaw src/types/hooks.ts.

/// Hook event types that can trigger callbacks.
enum HookEventType {
  preToolUse,
  postToolUse,
  userPromptSubmit,
  sessionStart,
  sessionEnd,
  setup,
  notification,
}

/// A prompt request for user elicitation.
class PromptRequest {
  final String type;
  final String? message;
  final List<String>? options;
  final String? defaultValue;

  const PromptRequest({
    required this.type,
    this.message,
    this.options,
    this.defaultValue,
  });
}

/// User's response to a prompt request.
class PromptResponse {
  final String? value;
  final bool cancelled;

  const PromptResponse({this.value, this.cancelled = false});
}

/// Progress event for hook execution.
class HookProgress {
  final String? message;
  final double? percentage;

  const HookProgress({this.message, this.percentage});
}

/// Error that blocks execution.
class HookBlockingError {
  final String message;
  final String? toolName;

  const HookBlockingError({required this.message, this.toolName});
}

/// Result of a permission request.
class PermissionRequestResult {
  final bool allowed;
  final String? reason;
  final Map<String, dynamic>? metadata;

  const PermissionRequestResult({
    required this.allowed,
    this.reason,
    this.metadata,
  });
}

/// Hook decision for whether to proceed.
enum HookDecision { allow, deny, ask }

/// Result of a single hook execution.
class HookResult {
  final HookDecision decision;
  final String? message;
  final String? hookName;
  final Duration? duration;

  const HookResult({
    required this.decision,
    this.message,
    this.hookName,
    this.duration,
  });
}

/// Aggregated results from multiple hooks.
class AggregatedHookResult {
  final HookDecision decision;
  final List<HookResult> results;
  final String? blockingMessage;

  const AggregatedHookResult({
    required this.decision,
    this.results = const [],
    this.blockingMessage,
  });
}

/// Hook callback definition.
class HookCallback {
  final String name;
  final HookEventType event;
  final Duration? timeout;
  final bool internal;
  final Future<HookResult> Function(Map<String, dynamic> context) callback;

  const HookCallback({
    required this.name,
    required this.event,
    required this.callback,
    this.timeout,
    this.internal = false,
  });
}

/// Matcher config for hook callbacks.
class HookCallbackMatcher {
  final String? toolName;
  final RegExp? toolNamePattern;

  const HookCallbackMatcher({this.toolName, this.toolNamePattern});

  bool matches(String name) {
    if (toolName != null && toolName == name) return true;
    if (toolNamePattern != null && toolNamePattern!.hasMatch(name)) return true;
    return toolName == null && toolNamePattern == null;
  }
}
