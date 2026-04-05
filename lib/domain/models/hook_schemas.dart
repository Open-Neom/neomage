// Hook configuration schemas — ported from Neomage src/schemas/hooks.ts.
// Defines the 4 hook implementation types: command, prompt, http, agent.

/// Base properties shared by all hook types.
abstract class HookConfig {
  /// Hook type discriminator.
  String get type;

  /// Permission rule filter (e.g., "Bash(git *)").
  String? get ifFilter;

  /// Timeout in seconds.
  int? get timeout;

  /// Custom spinner message during execution.
  String? get statusMessage;

  /// Run once and remove.
  bool get once;
}

/// Shell command hook — executes a bash/powershell command.
class BashCommandHook implements HookConfig {
  @override
  String get type => 'command';

  final String command;
  final String shell;
  final bool async;

  @override
  final String? ifFilter;
  @override
  final int? timeout;
  @override
  final String? statusMessage;
  @override
  final bool once;

  const BashCommandHook({
    required this.command,
    this.shell = 'bash',
    this.async = false,
    this.ifFilter,
    this.timeout,
    this.statusMessage,
    this.once = false,
  });
}

/// LLM prompt evaluation hook — sends context to a model for evaluation.
class PromptHook implements HookConfig {
  @override
  String get type => 'prompt';

  final String prompt;
  final String? model;

  @override
  final String? ifFilter;
  @override
  final int? timeout;
  @override
  final String? statusMessage;
  @override
  final bool once;

  const PromptHook({
    required this.prompt,
    this.model,
    this.ifFilter,
    this.timeout,
    this.statusMessage,
    this.once = false,
  });
}

/// HTTP webhook — sends a POST request to an endpoint.
class HttpHook implements HookConfig {
  @override
  String get type => 'http';

  final String url;
  final Map<String, String> headers;

  @override
  final String? ifFilter;
  @override
  final int? timeout;
  @override
  final String? statusMessage;
  @override
  final bool once;

  const HttpHook({
    required this.url,
    this.headers = const {},
    this.ifFilter,
    this.timeout,
    this.statusMessage,
    this.once = false,
  });
}

/// Agent hook — runs an agentic verifier.
class AgentHook implements HookConfig {
  @override
  String get type => 'agent';

  final String prompt;
  final String? model;

  @override
  final String? ifFilter;
  @override
  final int? timeout;
  @override
  final String? statusMessage;
  @override
  final bool once;

  const AgentHook({
    required this.prompt,
    this.model,
    this.ifFilter,
    this.timeout,
    this.statusMessage,
    this.once = false,
  });
}

/// Hook matcher — pattern matching on tool names with associated hooks.
class HookMatcher {
  final String? toolNamePattern;
  final List<HookConfig> hooks;

  const HookMatcher({this.toolNamePattern, required this.hooks});
}

/// Complete hooks configuration keyed by event type.
typedef HooksSettings = Map<String, List<HookMatcher>>;
