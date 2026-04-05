// SDK entrypoint types — ported from Neomage src/entrypoints/.

/// Hook event types that can be registered.
enum HookEvent {
  preToolUse,
  postToolUse,
  postToolUseFailure,
  notification,
  userPromptSubmit,
  sessionStart,
  sessionEnd,
  stop,
  stopFailure,
  subagentStart,
  subagentStop,
  preCompact,
  postCompact,
  permissionRequest,
  permissionDenied,
  setup,
  teammateIdle,
  taskCreated,
  taskCompleted,
  elicitation,
  elicitationResult,
  configChange,
  worktreeCreate,
  worktreeRemove,
  instructionsLoaded,
  cwdChanged,
  fileChanged,
}

/// Reasons a session can exit.
enum ExitReason {
  clear,
  resume,
  logout,
  promptInputExit,
  other,
  bypassPermissionsDisabled,
}

/// Sandbox network configuration.
class SandboxNetworkConfig {
  final List<String> allowedDomains;
  final List<String> allowedUnixSockets;
  final List<int> allowedProxyPorts;

  const SandboxNetworkConfig({
    this.allowedDomains = const [],
    this.allowedUnixSockets = const [],
    this.allowedProxyPorts = const [],
  });
}

/// Sandbox filesystem configuration.
class SandboxFilesystemConfig {
  final List<String> readAllowPaths;
  final List<String> writeAllowPaths;
  final List<String> readDenyPaths;
  final List<String> writeDenyPaths;

  const SandboxFilesystemConfig({
    this.readAllowPaths = const [],
    this.writeAllowPaths = const [],
    this.readDenyPaths = const [],
    this.writeDenyPaths = const [],
  });
}

/// Overall sandbox settings.
class SandboxSettings {
  final bool enabled;
  final bool failIfUnavailable;
  final bool autoAllowBashIfSandboxed;
  final SandboxNetworkConfig? network;
  final SandboxFilesystemConfig? filesystem;
  final List<String> ignoredViolations;

  const SandboxSettings({
    this.enabled = false,
    this.failIfUnavailable = false,
    this.autoAllowBashIfSandboxed = false,
    this.network,
    this.filesystem,
    this.ignoredViolations = const [],
  });
}

/// Output style configuration.
class OutputStyleConfig {
  final String name;
  final String description;
  final String prompt;
  final OutputStyleSource source;
  final bool keepCodingInstructions;

  const OutputStyleConfig({
    required this.name,
    required this.description,
    required this.prompt,
    required this.source,
    this.keepCodingInstructions = true,
  });
}

/// Source of an output style.
enum OutputStyleSource { project, user }
