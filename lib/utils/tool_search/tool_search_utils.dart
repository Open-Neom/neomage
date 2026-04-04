/// Tool Search utilities for dynamically discovering deferred tools.
///
/// When enabled, deferred tools (MCP and shouldDefer tools) are sent with
/// defer_loading: true and discovered via ToolSearchTool rather than being
/// loaded upfront.
///
/// Also includes tool error formatting, tool pool management, and tool schema
/// caching.
library;

import 'dart:convert';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Tool Search Mode
// ---------------------------------------------------------------------------

/// Tool search mode. Determines how deferrable tools (MCP + shouldDefer) are
/// surfaced:
///   - [tst]: Tool Search Tool -- deferred tools discovered via ToolSearchTool
///   - [tstAuto]: auto -- tools deferred only when they exceed threshold
///   - [standard]: tool search disabled -- all tools exposed inline
enum ToolSearchMode { tst, tstAuto, standard }

// ---------------------------------------------------------------------------
// Install Status (for tool pool operations)
// ---------------------------------------------------------------------------

/// Status of a tool installation or pool operation.
enum InstallStatus { success, noPermissions, installFailed, inProgress }

// ---------------------------------------------------------------------------
// Tool Definition
// ---------------------------------------------------------------------------

/// Represents a tool definition with metadata for search and filtering.
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic>? inputSchema;
  final Map<String, dynamic>? inputJsonSchema;
  final bool isMcp;
  final bool shouldDefer;
  final bool renderGroupedToolUse;

  const ToolDefinition({
    required this.name,
    this.description = '',
    this.inputSchema,
    this.inputJsonSchema,
    this.isMcp = false,
    this.shouldDefer = false,
    this.renderGroupedToolUse = false,
  });

  /// Whether this tool is a deferred tool (MCP or shouldDefer).
  bool get isDeferred => isMcp || shouldDefer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolDefinition &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

// ---------------------------------------------------------------------------
// Agent Definition
// ---------------------------------------------------------------------------

/// Represents an agent definition for tool search context.
class AgentDefinition {
  final String name;
  final String description;
  final List<String> allowedTools;

  const AgentDefinition({
    required this.name,
    this.description = '',
    this.allowedTools = const [],
  });
}

// ---------------------------------------------------------------------------
// Tool Permission Context
// ---------------------------------------------------------------------------

/// Context for tool permission checks.
class ToolPermissionContext {
  final String mode;
  final Map<String, dynamic> metadata;

  const ToolPermissionContext({required this.mode, this.metadata = const {}});
}

// ---------------------------------------------------------------------------
// Deferred Tools Delta
// ---------------------------------------------------------------------------

/// Represents changes to the deferred tool pool.
class DeferredToolsDelta {
  final List<String> addedNames;
  final List<String> addedLines;
  final List<String> removedNames;

  const DeferredToolsDelta({
    required this.addedNames,
    required this.addedLines,
    required this.removedNames,
  });
}

/// Call-site discriminator for delta scan events.
enum DeferredToolsDeltaScanCallSite {
  attachmentsMain,
  attachmentsSubagent,
  compactFull,
  compactPartial,
  reactiveCompact,
}

/// Context for deferred tools delta scanning.
class DeferredToolsDeltaScanContext {
  final DeferredToolsDeltaScanCallSite callSite;
  final String? querySource;

  const DeferredToolsDeltaScanContext({
    required this.callSite,
    this.querySource,
  });
}

// ---------------------------------------------------------------------------
// Message types for tool_reference extraction
// ---------------------------------------------------------------------------

/// Minimal message representation for tool reference extraction.
class ToolSearchMessage {
  final String type;
  final String? subtype;
  final Map<String, dynamic>? message;
  final Map<String, dynamic>? compactMetadata;
  final Map<String, dynamic>? attachment;

  const ToolSearchMessage({
    required this.type,
    this.subtype,
    this.message,
    this.compactMetadata,
    this.attachment,
  });
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Default percentage of context window at which to auto-enable tool search.
const int _defaultAutoToolSearchPercentage = 10;

/// Approximate chars per token for MCP tool definitions.
const double _charsPerToken = 2.5;

/// Tool search tool name constant.
const String toolSearchToolName = 'ToolSearchTool';

/// Token count overhead for tool definitions.
const int toolTokenCountOverhead = 200;

/// Default patterns for models that do NOT support tool_reference.
const List<String> _defaultUnsupportedModelPatterns = ['haiku'];

/// Name used for the interrupt sentinel.
const String interruptMessageForToolUse =
    'The user has interrupted the tool use.';

// ---------------------------------------------------------------------------
// Tool Search Controller
// ---------------------------------------------------------------------------

/// Controller for tool search state and operations.
///
/// Manages the tool search indexing, mode detection, and deferred tool
/// discovery lifecycle using Sint reactive state management.
class ToolSearchController extends SintController {
  /// Current tool search mode.
  final Rx<ToolSearchMode> mode = ToolSearchMode.tst.obs;

  /// Whether tool search has been optimistically enabled.
  final RxBool optimisticEnabled = false.obs;

  /// Set of discovered tool names from message history.
  final RxSet<String> discoveredToolNames = <String>{}.obs;

  /// Cached deferred tool token count (null if not yet computed).
  final Rxn<int> deferredToolTokenCount = Rxn<int>();

  /// Whether the optimistic check has been logged.
  bool _loggedOptimistic = false;

  /// Environment configuration (injectable for testing).
  final Map<String, String> _envConfig;

  /// Unsupported model patterns (can be updated from remote config).
  List<String> _unsupportedModelPatterns = List.from(
    _defaultUnsupportedModelPatterns,
  );

  ToolSearchController({Map<String, String>? envConfig})
    : _envConfig = envConfig ?? {};

  @override
  void onInit() {
    super.onInit();
    mode.value = getToolSearchMode();
    optimisticEnabled.value = isToolSearchEnabledOptimistic();
  }

  /// Update environment config at runtime.
  void updateEnvConfig(Map<String, String> config) {
    _envConfig.addAll(config);
    mode.value = getToolSearchMode();
    optimisticEnabled.value = isToolSearchEnabledOptimistic();
  }

  /// Update unsupported model patterns from remote configuration.
  void updateUnsupportedModelPatterns(List<String> patterns) {
    if (patterns.isNotEmpty) {
      _unsupportedModelPatterns = patterns;
    }
  }

  // -------------------------------------------------------------------------
  // Auto percentage parsing
  // -------------------------------------------------------------------------

  /// Parse auto:N syntax from ENABLE_TOOL_SEARCH env var.
  /// Returns the percentage clamped to 0-100, or null if not auto:N format.
  int? _parseAutoPercentage(String value) {
    if (!value.startsWith('auto:')) return null;

    final percentStr = value.substring(5);
    final percent = int.tryParse(percentStr);

    if (percent == null) {
      _logDebug(
        'Invalid ENABLE_TOOL_SEARCH value "$value": '
        'expected auto:N where N is a number.',
      );
      return null;
    }

    return percent.clamp(0, 100);
  }

  /// Check if ENABLE_TOOL_SEARCH is set to auto mode.
  bool _isAutoToolSearchMode(String? value) {
    if (value == null || value.isEmpty) return false;
    return value == 'auto' || value.startsWith('auto:');
  }

  /// Get the auto-enable percentage from env var or default.
  int _getAutoToolSearchPercentage() {
    final value = _envConfig['ENABLE_TOOL_SEARCH'];
    if (value == null || value.isEmpty) return _defaultAutoToolSearchPercentage;
    if (value == 'auto') return _defaultAutoToolSearchPercentage;

    final parsed = _parseAutoPercentage(value);
    if (parsed != null) return parsed;

    return _defaultAutoToolSearchPercentage;
  }

  // -------------------------------------------------------------------------
  // Token / char thresholds
  // -------------------------------------------------------------------------

  /// Get the token threshold for auto-enabling tool search for a given model.
  int getAutoToolSearchTokenThreshold({
    required String model,
    required int contextWindow,
  }) {
    final percentage = _getAutoToolSearchPercentage() / 100;
    return (contextWindow * percentage).floor();
  }

  /// Get the character threshold for auto-enabling tool search for a given model.
  int getAutoToolSearchCharThreshold({
    required String model,
    required int contextWindow,
  }) {
    return (getAutoToolSearchTokenThreshold(
              model: model,
              contextWindow: contextWindow,
            ) *
            _charsPerToken)
        .floor();
  }

  // -------------------------------------------------------------------------
  // Model support
  // -------------------------------------------------------------------------

  /// Check if a model supports tool_reference blocks (required for tool search).
  ///
  /// Uses a negative test: models are assumed to support tool_reference
  /// UNLESS they match a pattern in the unsupported list.
  bool modelSupportsToolReference(String model) {
    final normalizedModel = model.toLowerCase();
    for (final pattern in _unsupportedModelPatterns) {
      if (normalizedModel.contains(pattern.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Mode detection
  // -------------------------------------------------------------------------

  /// Determines the tool search mode from configuration.
  ToolSearchMode getToolSearchMode() {
    if (_isEnvTruthy(_envConfig['NEOMCLAW_DISABLE_EXPERIMENTAL_BETAS'])) {
      return ToolSearchMode.standard;
    }

    final value = _envConfig['ENABLE_TOOL_SEARCH'];

    final autoPercent = (value != null) ? _parseAutoPercentage(value) : null;
    if (autoPercent == 0) return ToolSearchMode.tst;
    if (autoPercent == 100) return ToolSearchMode.standard;
    if (_isAutoToolSearchMode(value)) return ToolSearchMode.tstAuto;

    if (_isEnvTruthy(value)) return ToolSearchMode.tst;
    if (_isEnvDefinedFalsy(_envConfig['ENABLE_TOOL_SEARCH'])) {
      return ToolSearchMode.standard;
    }
    return ToolSearchMode.tst; // default
  }

  /// Optimistic check -- returns true if tool search could potentially be
  /// enabled, without checking dynamic factors like model support or threshold.
  bool isToolSearchEnabledOptimistic() {
    final currentMode = getToolSearchMode();
    if (currentMode == ToolSearchMode.standard) {
      if (!_loggedOptimistic) {
        _loggedOptimistic = true;
        _logDebug(
          '[ToolSearch:optimistic] mode=$currentMode, '
          'ENABLE_TOOL_SEARCH=${_envConfig['ENABLE_TOOL_SEARCH']}, result=false',
        );
      }
      return false;
    }

    // Third-party API gateways may not support tool_reference.
    final enableToolSearch = _envConfig['ENABLE_TOOL_SEARCH'];
    if ((enableToolSearch == null || enableToolSearch.isEmpty) &&
        _getApiProvider() == 'firstParty' &&
        !_isFirstPartyAnthropicBaseUrl()) {
      if (!_loggedOptimistic) {
        _loggedOptimistic = true;
        _logDebug(
          '[ToolSearch:optimistic] disabled: ANTHROPIC_BASE_URL='
          '${_envConfig['ANTHROPIC_BASE_URL']} is not a first-party host.',
        );
      }
      return false;
    }

    if (!_loggedOptimistic) {
      _loggedOptimistic = true;
      _logDebug(
        '[ToolSearch:optimistic] mode=$currentMode, '
        'ENABLE_TOOL_SEARCH=${_envConfig['ENABLE_TOOL_SEARCH']}, result=true',
      );
    }
    return true;
  }

  /// Check if ToolSearchTool is available in the provided tools list.
  bool isToolSearchToolAvailable(List<ToolDefinition> tools) {
    return tools.any((tool) => _toolMatchesName(tool, toolSearchToolName));
  }

  // -------------------------------------------------------------------------
  // Deferred tool description size
  // -------------------------------------------------------------------------

  /// Calculate total deferred tool description size in characters.
  int calculateDeferredToolDescriptionChars(List<ToolDefinition> tools) {
    final deferredTools = tools.where((t) => t.isDeferred).toList();
    if (deferredTools.isEmpty) return 0;

    int total = 0;
    for (final tool in deferredTools) {
      final schemaStr = tool.inputJsonSchema != null
          ? jsonEncode(tool.inputJsonSchema)
          : tool.inputSchema != null
          ? jsonEncode(tool.inputSchema)
          : '';
      total += tool.name.length + tool.description.length + schemaStr.length;
    }
    return total;
  }

  // -------------------------------------------------------------------------
  // Full enabled check
  // -------------------------------------------------------------------------

  /// Check if tool search is enabled for a specific request.
  ///
  /// This is the definitive check that includes model compatibility,
  /// ToolSearchTool availability, and threshold check for auto mode.
  Future<bool> isToolSearchEnabled({
    required String model,
    required List<ToolDefinition> tools,
    required int contextWindow,
    String? source,
  }) async {
    if (!modelSupportsToolReference(model)) {
      _logDebug(
        'Tool search disabled for model \'$model\': '
        'model does not support tool_reference blocks.',
      );
      return false;
    }

    if (!isToolSearchToolAvailable(tools)) {
      _logDebug('Tool search disabled: ToolSearchTool is not available.');
      return false;
    }

    final currentMode = getToolSearchMode();

    switch (currentMode) {
      case ToolSearchMode.tst:
        return true;

      case ToolSearchMode.tstAuto:
        final result = _checkAutoThreshold(
          tools: tools,
          model: model,
          contextWindow: contextWindow,
        );
        if (result.enabled) {
          _logDebug(
            'Auto tool search enabled: ${result.debugDescription}'
            '${source != null ? ' [source: $source]' : ''}',
          );
        } else {
          _logDebug(
            'Auto tool search disabled: ${result.debugDescription}'
            '${source != null ? ' [source: $source]' : ''}',
          );
        }
        return result.enabled;

      case ToolSearchMode.standard:
        return false;
    }
  }

  // -------------------------------------------------------------------------
  // Auto-threshold check
  // -------------------------------------------------------------------------

  _AutoThresholdResult _checkAutoThreshold({
    required List<ToolDefinition> tools,
    required String model,
    required int contextWindow,
  }) {
    // Use character-based heuristic
    final deferredToolDescriptionChars = calculateDeferredToolDescriptionChars(
      tools,
    );
    final charThreshold = getAutoToolSearchCharThreshold(
      model: model,
      contextWindow: contextWindow,
    );
    return _AutoThresholdResult(
      enabled: deferredToolDescriptionChars >= charThreshold,
      debugDescription:
          '$deferredToolDescriptionChars chars (threshold: $charThreshold, '
          '${_getAutoToolSearchPercentage()}% of context) (char fallback)',
      metrics: {
        'deferredToolDescriptionChars': deferredToolDescriptionChars,
        'charThreshold': charThreshold,
      },
    );
  }

  // -------------------------------------------------------------------------
  // Tool reference extraction
  // -------------------------------------------------------------------------

  /// Check if an object map represents a tool_reference block.
  static bool isToolReferenceBlock(Map<String, dynamic>? obj) {
    if (obj == null) return false;
    return obj['type'] == 'tool_reference';
  }

  /// Check if an object is a tool_reference with a tool_name.
  static bool isToolReferenceWithName(Map<String, dynamic>? obj) {
    if (!isToolReferenceBlock(obj)) return false;
    return obj!['tool_name'] is String;
  }

  /// Check if an object is a tool_result block with array content.
  static bool isToolResultBlockWithContent(Map<String, dynamic>? obj) {
    if (obj == null) return false;
    return obj['type'] == 'tool_result' && obj['content'] is List;
  }

  /// Extract tool names from tool_reference blocks in message history.
  ///
  /// When dynamic tool loading is enabled, MCP tools are not predeclared.
  /// Instead, they are discovered via ToolSearchTool which returns
  /// tool_reference blocks.
  Set<String> extractDiscoveredToolNames(List<ToolSearchMessage> messages) {
    final discovered = <String>{};
    int carriedFromBoundary = 0;

    for (final msg in messages) {
      // Compact boundary carries the pre-compact discovered set.
      if (msg.type == 'system' && msg.subtype == 'compact_boundary') {
        final carried = msg.compactMetadata?['preCompactDiscoveredTools'];
        if (carried is List) {
          for (final name in carried) {
            if (name is String) {
              discovered.add(name);
              carriedFromBoundary++;
            }
          }
        }
        continue;
      }

      if (msg.type != 'user') continue;

      final content = msg.message?['content'];
      if (content is! List) continue;

      for (final block in content) {
        if (block is! Map<String, dynamic>) continue;
        if (isToolResultBlockWithContent(block)) {
          final blockContent = block['content'] as List;
          for (final item in blockContent) {
            if (item is Map<String, dynamic> && isToolReferenceWithName(item)) {
              discovered.add(item['tool_name'] as String);
            }
          }
        }
      }
    }

    if (discovered.isNotEmpty) {
      _logDebug(
        'Dynamic tool loading: found ${discovered.length} discovered tools'
        '${carriedFromBoundary > 0 ? ' ($carriedFromBoundary carried from compact boundary)' : ''}',
      );
    }

    discoveredToolNames.value = discovered;
    return discovered;
  }

  // -------------------------------------------------------------------------
  // Deferred tools delta
  // -------------------------------------------------------------------------

  /// Whether deferred tools delta attachments are enabled.
  bool isDeferredToolsDeltaEnabled() {
    return _envConfig['USER_TYPE'] == 'ant';
  }

  /// Diff the current deferred-tool pool against what has been announced.
  ///
  /// Returns null if nothing changed. A name that was announced but has since
  /// stopped being deferred -- yet is still in the base pool -- is NOT
  /// reported as removed.
  DeferredToolsDelta? getDeferredToolsDelta({
    required List<ToolDefinition> tools,
    required List<ToolSearchMessage> messages,
    DeferredToolsDeltaScanContext? scanContext,
  }) {
    final announced = <String>{};
    int _attachmentCount = 0;
    int _dtdCount = 0;
    final attachmentTypesSeen = <String>{};

    for (final msg in messages) {
      if (msg.type != 'attachment') continue;
      _attachmentCount++;
      final attachmentType = msg.attachment?['type'] as String?;
      if (attachmentType != null) attachmentTypesSeen.add(attachmentType);
      if (attachmentType != 'deferred_tools_delta') continue;
      _dtdCount++;
      final addedNames = msg.attachment?['addedNames'];
      if (addedNames is List) {
        for (final n in addedNames) {
          if (n is String) announced.add(n);
        }
      }
      final removedNames = msg.attachment?['removedNames'];
      if (removedNames is List) {
        for (final n in removedNames) {
          if (n is String) announced.remove(n);
        }
      }
    }

    final deferred = tools.where((t) => t.isDeferred).toList();
    final deferredNames = deferred.map((t) => t.name).toSet();
    final poolNames = tools.map((t) => t.name).toSet();

    final added = deferred.where((t) => !announced.contains(t.name)).toList();
    final removed = <String>[];
    for (final n in announced) {
      if (deferredNames.contains(n)) continue;
      if (!poolNames.contains(n)) removed.add(n);
    }

    if (added.isEmpty && removed.isEmpty) return null;

    return DeferredToolsDelta(
      addedNames: added.map((t) => t.name).toList()..sort(),
      addedLines: added.map(_formatDeferredToolLine).toList()..sort(),
      removedNames: removed..sort(),
    );
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  String _formatDeferredToolLine(ToolDefinition tool) {
    return '- ${tool.name}: ${tool.description}';
  }

  bool _toolMatchesName(ToolDefinition tool, String name) {
    return tool.name == name || tool.name.endsWith('__$name');
  }

  String _getApiProvider() {
    return _envConfig['API_PROVIDER'] ?? 'firstParty';
  }

  bool _isFirstPartyAnthropicBaseUrl() {
    final baseUrl = _envConfig['ANTHROPIC_BASE_URL'];
    if (baseUrl == null || baseUrl.isEmpty) return true;
    return baseUrl.contains('anthropic.com');
  }

  bool _isEnvTruthy(String? value) {
    if (value == null || value.isEmpty) return false;
    return ['true', '1', 'yes'].contains(value.toLowerCase());
  }

  bool _isEnvDefinedFalsy(String? value) {
    if (value == null) return false;
    return ['false', '0', 'no', ''].contains(value.toLowerCase());
  }

  void _logDebug(String message) {
    // In production, delegate to a logging service.
    assert(() {
      // ignore: avoid_print
      print('[ToolSearch] $message');
      return true;
    }());
  }
}

// ---------------------------------------------------------------------------
// Auto-threshold result (internal)
// ---------------------------------------------------------------------------

class _AutoThresholdResult {
  final bool enabled;
  final String debugDescription;
  final Map<String, int> metrics;

  const _AutoThresholdResult({
    required this.enabled,
    required this.debugDescription,
    required this.metrics,
  });
}

// ===========================================================================
// Tool Errors (ported from toolErrors.ts)
// ===========================================================================

/// Custom error for shell command failures.
class ShellError implements Exception {
  final int code;
  final String stdout;
  final String stderr;
  final bool interrupted;
  final String? message;

  const ShellError({
    required this.code,
    this.stdout = '',
    this.stderr = '',
    this.interrupted = false,
    this.message,
  });

  @override
  String toString() => 'ShellError(code: $code, message: $message)';
}

/// Custom error for user-initiated aborts.
class AbortError implements Exception {
  final String message;
  const AbortError([this.message = '']);

  @override
  String toString() => 'AbortError: $message';
}

/// Formats an error into a human-readable string, with truncation for
/// very long messages.
String formatError(Object error) {
  if (error is AbortError) {
    return error.message.isNotEmpty
        ? error.message
        : interruptMessageForToolUse;
  }
  if (error is! Exception && error is! Error) {
    return error.toString();
  }

  final parts = getErrorParts(error);
  final fullMessage = parts.where((p) => p.isNotEmpty).join('\n').trim();
  final result = fullMessage.isEmpty
      ? 'Command failed with no output'
      : fullMessage;

  if (result.length <= 10000) return result;

  const halfLength = 5000;
  final start = result.substring(0, halfLength);
  final end = result.substring(result.length - halfLength);
  return '$start\n\n... [${result.length - 10000} characters truncated] ...\n\n$end';
}

/// Extracts error parts from a structured error.
List<String> getErrorParts(Object error) {
  if (error is ShellError) {
    return [
      'Exit code ${error.code}',
      if (error.interrupted) interruptMessageForToolUse else '',
      error.stderr,
      error.stdout,
    ];
  }
  final parts = <String>[];
  if (error is Exception) {
    parts.add(error.toString());
  } else if (error is Error) {
    parts.add(error.toString());
  }
  return parts;
}

/// Formats a validation path into a readable string.
/// e.g., ['todos', 0, 'activeForm'] => 'todos[0].activeForm'
String formatValidationPath(List<dynamic> path) {
  if (path.isEmpty) return '';

  final buffer = StringBuffer();
  for (int i = 0; i < path.length; i++) {
    final segment = path[i];
    if (segment is int) {
      buffer.write('[$segment]');
    } else {
      if (i == 0) {
        buffer.write(segment.toString());
      } else {
        buffer.write('.${segment.toString()}');
      }
    }
  }
  return buffer.toString();
}

/// Validation issue types for structured error formatting.
sealed class ValidationIssue {
  const ValidationIssue();
}

/// A required parameter is missing.
class MissingParamIssue extends ValidationIssue {
  final String param;
  const MissingParamIssue(this.param);
}

/// An unexpected parameter was provided.
class UnexpectedParamIssue extends ValidationIssue {
  final String param;
  const UnexpectedParamIssue(this.param);
}

/// A parameter has an incorrect type.
class TypeMismatchIssue extends ValidationIssue {
  final String param;
  final String expected;
  final String received;
  const TypeMismatchIssue({
    required this.param,
    required this.expected,
    required this.received,
  });
}

/// Converts validation errors into a human-readable and LLM-friendly
/// error message.
String formatValidationError({
  required String toolName,
  required List<ValidationIssue> issues,
  String? fallbackMessage,
}) {
  final errorParts = <String>[];

  for (final issue in issues) {
    switch (issue) {
      case MissingParamIssue(:final param):
        errorParts.add('The required parameter `$param` is missing');
      case UnexpectedParamIssue(:final param):
        errorParts.add('An unexpected parameter `$param` was provided');
      case TypeMismatchIssue(:final param, :final expected, :final received):
        errorParts.add(
          'The parameter `$param` type is expected as `$expected` '
          'but provided as `$received`',
        );
    }
  }

  if (errorParts.isEmpty) {
    return fallbackMessage ?? 'Validation failed for $toolName';
  }

  final issueWord = errorParts.length > 1 ? 'issues' : 'issue';
  return '$toolName failed due to the following $issueWord:\n'
      '${errorParts.join('\n')}';
}

// ===========================================================================
// Tool Pool (ported from toolPool.ts)
// ===========================================================================

/// Known tool name suffixes for PR activity subscription.
const List<String> _prActivityToolSuffixes = [
  'subscribe_pr_activity',
  'unsubscribe_pr_activity',
];

/// Check if a tool name is a PR activity subscription tool.
bool isPrActivitySubscriptionTool(String name) {
  return _prActivityToolSuffixes.any((suffix) => name.endsWith(suffix));
}

/// Filters a tool list to the set allowed in coordinator mode.
///
/// PR activity subscription tools are always allowed since subscription
/// management is orchestration.
List<ToolDefinition> applyCoordinatorToolFilter({
  required List<ToolDefinition> tools,
  required Set<String> coordinatorAllowedTools,
}) {
  return tools
      .where(
        (t) =>
            coordinatorAllowedTools.contains(t.name) ||
            isPrActivitySubscriptionTool(t.name),
      )
      .toList();
}

/// Pure function that merges tool pools and applies coordinator mode filtering.
///
/// [initialTools] - Extra tools to include (built-in + startup MCP from props).
/// [assembled] - Tools from assembleToolPool (built-in + MCP, deduped).
/// [mode] - The permission context mode.
/// [isCoordinatorMode] - Whether coordinator mode is active.
/// [coordinatorAllowedTools] - Set of tool names allowed in coordinator mode.
List<ToolDefinition> mergeAndFilterTools({
  required List<ToolDefinition> initialTools,
  required List<ToolDefinition> assembled,
  required String mode,
  bool isCoordinatorMode = false,
  Set<String>? coordinatorAllowedTools,
}) {
  // Merge initialTools on top - they take precedence in deduplication.
  final seen = <String>{};
  final merged = <ToolDefinition>[];

  for (final tool in [...initialTools, ...assembled]) {
    if (seen.add(tool.name)) {
      merged.add(tool);
    }
  }

  // Partition: built-ins first, then MCP tools, each sorted by name.
  final mcpTools = merged.where((t) => t.isMcp).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final builtInTools = merged.where((t) => !t.isMcp).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final tools = [...builtInTools, ...mcpTools];

  if (isCoordinatorMode && coordinatorAllowedTools != null) {
    return applyCoordinatorToolFilter(
      tools: tools,
      coordinatorAllowedTools: coordinatorAllowedTools,
    );
  }

  return tools;
}

// ===========================================================================
// Tool Schema Cache (ported from toolSchemaCache.ts)
// ===========================================================================

/// Cached tool schema entry.
class CachedToolSchema {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;
  final bool? strict;
  final bool? eagerInputStreaming;

  const CachedToolSchema({
    required this.name,
    this.description,
    this.inputSchema,
    this.strict,
    this.eagerInputStreaming,
  });
}

/// Session-scoped cache of rendered tool schemas.
///
/// Tool schemas render at server position 2 (before system prompt), so any
/// byte-level change busts the entire tool block AND everything downstream.
/// Memoizing per-session locks the schema bytes at first render.
class ToolSchemaCache {
  final Map<String, CachedToolSchema> _cache = {};

  /// Get the full cache map.
  Map<String, CachedToolSchema> get entries => Map.unmodifiable(_cache);

  /// Get a cached schema by tool name.
  CachedToolSchema? get(String name) => _cache[name];

  /// Store a schema in the cache.
  void set(String name, CachedToolSchema schema) {
    _cache[name] = schema;
  }

  /// Check if the cache contains a schema for the given name.
  bool has(String name) => _cache.containsKey(name);

  /// Clear the entire cache.
  void clear() => _cache.clear();

  /// Number of cached schemas.
  int get size => _cache.length;
}

/// Global tool schema cache instance.
final toolSchemaCache = ToolSchemaCache();

/// Clear the global tool schema cache.
void clearToolSchemaCache() => toolSchemaCache.clear();
