// Enhanced tool base — ported from Neomage src/Tool.ts.

import '../../domain/models/permissions.dart';
import '../../domain/models/tool_definition.dart';

/// Result of executing a tool.
class ToolResult {
  final String content;
  final bool isError;
  final Map<String, dynamic>? metadata;

  /// Additional messages to inject into conversation after tool execution.
  final List<Map<String, dynamic>>? newMessages;

  const ToolResult({
    required this.content,
    this.isError = false,
    this.metadata,
    this.newMessages,
  });

  factory ToolResult.success(
    String content, {
    Map<String, dynamic>? metadata,
  }) => ToolResult(content: content, metadata: metadata);

  factory ToolResult.error(String message) =>
      ToolResult(content: message, isError: true);
}

/// Result of validating tool input.
class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult.valid() : isValid = true, error = null;
  const ValidationResult.invalid(String message)
    : isValid = false,
      error = message;
}

/// Tool interrupt behavior when user sends a new message.
enum InterruptBehavior {
  /// Tool can be interrupted immediately.
  interruptible,

  /// Tool should finish current operation before yielding.
  finishThenYield,

  /// Tool cannot be interrupted.
  nonInterruptible,
}

/// Context provided to tools during execution.
class ToolUseContext {
  final String cwd;
  final bool debugMode;
  final AbortSignal? abortSignal;
  final void Function(String)? onProgress;

  const ToolUseContext({
    required this.cwd,
    this.debugMode = false,
    this.abortSignal,
    this.onProgress,
  });
}

/// Simple abort signal for cancellation support.
class AbortSignal {
  bool _aborted = false;
  bool get isAborted => _aborted;
  void abort() => _aborted = true;
}

/// Abstract base for all tools.
/// Enhanced port of neomage/src/Tool.ts with permissions, safety flags,
/// and execution context.
abstract class Tool {
  /// Tool name as registered with the API.
  String get name;

  /// Human-readable description.
  String get description;

  /// Detailed prompt text sent in the system prompt for this tool.
  String get prompt => description;

  /// JSON Schema for the tool's input parameters.
  Map<String, dynamic> get inputSchema;

  /// Execute the tool with the given input.
  Future<ToolResult> execute(Map<String, dynamic> input);

  /// Execute with full context (default delegates to simple execute).
  Future<ToolResult> call(Map<String, dynamic> input, ToolUseContext context) =>
      execute(input);

  // ── Availability ──

  /// Whether this tool is available on the current platform.
  bool get isAvailable => true;

  /// Whether this tool is enabled (can be toggled by config).
  bool get isEnabled => true;

  // ── Safety Flags ──

  /// Whether this tool only reads data (no side effects).
  bool get isReadOnly => false;

  /// Whether this tool can cause destructive changes.
  bool get isDestructive => false;

  /// Whether this tool is safe to run concurrently with other tools.
  bool get isConcurrencySafe => false;

  /// Whether this tool requires user interaction (prompts, confirmations).
  bool get requiresUserInteraction => false;

  /// How this tool behaves when interrupted by user input.
  InterruptBehavior get interruptBehavior => InterruptBehavior.interruptible;

  // ── Permissions ──

  /// Check if this tool use is permitted. Returns a PermissionDecision.
  /// Override in subclasses for tool-specific permission logic.
  Future<PermissionDecision> checkPermissions(
    Map<String, dynamic> input,
    ToolPermissionContext permContext,
  ) async {
    return const AllowDecision(PermissionAllowDecision());
  }

  /// Validate input before execution and permission checks.
  ValidationResult validateInput(Map<String, dynamic> input) {
    return const ValidationResult.valid();
  }

  /// Generate classifier input for auto-permission decisions.
  /// Returns empty string to skip classification.
  String toAutoClassifierInput(Map<String, dynamic> input) => '';

  /// Human-facing name for display in permission prompts.
  String get userFacingName => name;

  /// Permission explanation for this tool.
  PermissionExplanation? getPermissionExplanation(Map<String, dynamic> input) =>
      null;

  // ── Result Handling ──

  /// Maximum size in characters for tool results before disk persistence.
  int? get maxResultSizeChars => null;

  /// Whether this tool enforces strict JSON output.
  bool get strict => false;

  // ── Deferred Tool Support ──

  /// Whether this tool should be deferred (loaded on demand via ToolSearch).
  bool get shouldDefer => false;

  /// Whether this tool should always be loaded (never deferred).
  bool get alwaysLoad => true;

  // ── MCP ──

  /// Whether this tool comes from an MCP server.
  bool get isMcp => false;

  /// MCP server info if this is an MCP tool.
  Map<String, dynamic>? get mcpInfo => null;

  // ── Summary ──

  /// Short summary of tool use for compact/grouped display.
  String getToolUseSummary(Map<String, dynamic> input) => name;

  /// Activity description for status display.
  String getActivityDescription(Map<String, dynamic> input) =>
      'Using $userFacingName';

  // ── API Definition ──

  /// Convert to API tool definition.
  ToolDefinition get definition => ToolDefinition(
    name: name,
    description: description,
    inputSchema: inputSchema,
  );
}

/// Mixin for tools that execute shell commands.
mixin ShellToolMixin on Tool {
  @override
  bool get isDestructive => true;

  @override
  bool get isConcurrencySafe => false;

  @override
  InterruptBehavior get interruptBehavior => InterruptBehavior.finishThenYield;
}

/// Mixin for tools that only read files/data.
mixin ReadOnlyToolMixin on Tool {
  @override
  bool get isReadOnly => true;

  @override
  bool get isConcurrencySafe => true;

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, dynamic> input,
    ToolPermissionContext permContext,
  ) async {
    return const AllowDecision(PermissionAllowDecision());
  }
}

/// Mixin for tools that write/modify files.
mixin FileWriteToolMixin on Tool {
  @override
  bool get isDestructive => true;

  @override
  bool get isConcurrencySafe => false;
}
