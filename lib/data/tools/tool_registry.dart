// Tool registry — expanded port of NeomClaw's tool registration system.
// Manages tool registration, lookup, execution with hooks, categories,
// stats tracking, and schema access.

import 'dart:async';

import '../../domain/models/tool_definition.dart';
import 'tool.dart';

// ─── ToolCategory ────────────────────────────────────────────────────────────

/// Logical category for grouping tools.
enum ToolCategory {
  /// File read/write/edit operations.
  file,

  /// Search and pattern-matching (Glob, Grep).
  search,

  /// Web access (fetch, search).
  web,

  /// Agent / sub-agent tools.
  agent,

  /// System commands (Bash, PowerShell).
  system,

  /// Editor-specific tools (NotebookEdit, TodoWrite).
  editor,

  /// User-defined / plugin tools.
  custom,

  /// MCP (Model Context Protocol) server tools.
  mcp,
}

// ─── ToolRegistration ────────────────────────────────────────────────────────

/// Wraps a [Tool] with registry metadata.
class ToolRegistration {
  /// The underlying tool instance.
  final Tool tool;

  /// Logical category.
  final ToolCategory category;

  /// Whether this tool is currently enabled.
  bool enabled;

  /// Whether this tool is currently restricted (e.g. during plan mode).
  bool restricted;

  /// Total number of times this tool has been executed.
  int executionCount;

  /// Running average execution duration in milliseconds.
  double avgDurationMs;

  /// Timestamp of last execution.
  DateTime? lastExecutedAt;

  ToolRegistration({
    required this.tool,
    required this.category,
    this.enabled = true,
    this.restricted = false,
    this.executionCount = 0,
    this.avgDurationMs = 0,
    this.lastExecutedAt,
  });

  /// Tool name (delegates to inner tool).
  String get name => tool.name;

  /// Whether this tool can currently be executed.
  bool get isExecutable =>
      enabled && !restricted && tool.isAvailable && tool.isEnabled;

  /// Tool definition for API calls.
  ToolDefinition get definition => tool.definition;

  /// Update running average with a new sample.
  void recordExecution(Duration duration) {
    final ms = duration.inMilliseconds.toDouble();
    avgDurationMs =
        (avgDurationMs * executionCount + ms) / (executionCount + 1);
    executionCount++;
    lastExecutedAt = DateTime.now();
  }
}

// ─── ToolExecutionEvent ──────────────────────────────────────────────────────

/// Event emitted after a tool execution.
class ToolExecutionEvent {
  final String toolName;
  final ToolCategory category;
  final Duration duration;
  final bool isError;
  final DateTime timestamp;

  const ToolExecutionEvent({
    required this.toolName,
    required this.category,
    required this.duration,
    required this.isError,
    required this.timestamp,
  });
}

// ─── ToolStats ───────────────────────────────────────────────────────────────

/// Aggregate statistics for a single tool.
class ToolStats {
  final String name;
  final ToolCategory category;
  final int executionCount;
  final double avgDurationMs;
  final DateTime? lastExecutedAt;
  final bool enabled;
  final bool restricted;

  const ToolStats({
    required this.name,
    required this.category,
    required this.executionCount,
    required this.avgDurationMs,
    this.lastExecutedAt,
    required this.enabled,
    required this.restricted,
  });
}

// ─── ToolRegistry ────────────────────────────────────────────────────────────

/// Full-featured tool registry.
///
/// Manages tool registration/unregistration, lookup, execution with pre/post
/// hooks, enable/disable, restrict, stats tracking, schema access,
/// and fuzzy name matching.
class ToolRegistry {
  final Map<String, ToolRegistration> _tools = {};

  /// Pre-execution hooks. Return false to abort execution.
  final List<Future<bool> Function(String name, Map<String, dynamic> input)>
  _preHooks = [];

  /// Post-execution hooks.
  final List<void Function(ToolExecutionEvent event)> _postHooks = [];

  /// Stream controller for execution events.
  final _executionController = StreamController<ToolExecutionEvent>.broadcast();

  /// Stream of tool execution events.
  Stream<ToolExecutionEvent> get onToolExecuted => _executionController.stream;

  // ── Registration ─────────────────────────────────────────────────────────

  /// Register a tool with a category.
  void register(Tool tool, {ToolCategory category = ToolCategory.custom}) {
    _tools[tool.name] = ToolRegistration(tool: tool, category: category);
  }

  /// Unregister a tool by name.
  void unregister(String name) {
    _tools.remove(name);
  }

  // ── Lookup ───────────────────────────────────────────────────────────────

  /// Get a tool registration by name.
  ToolRegistration? getRegistration(String name) => _tools[name];

  /// Get a tool by name.
  Tool? get(String name) => _tools[name]?.tool;

  /// Get all registrations.
  Iterable<ToolRegistration> get allRegistrations => _tools.values;

  /// All registered tool names.
  Iterable<String> get names => _tools.keys;

  /// All registered tools.
  Iterable<Tool> get all => _tools.values.map((r) => r.tool);

  /// All currently executable tools.
  Iterable<Tool> get available =>
      _tools.values.where((r) => r.isExecutable).map((r) => r.tool);

  /// Tool definitions for API calls (only executable tools).
  List<ToolDefinition> get definitions => _tools.values
      .where((r) => r.isExecutable)
      .map((r) => r.definition)
      .toList();

  /// Get tools in a specific category.
  List<ToolRegistration> getByCategory(ToolCategory category) =>
      _tools.values.where((r) => r.category == category).toList();

  // ── Execution ────────────────────────────────────────────────────────────

  /// Execute a tool by name, running pre/post hooks and tracking stats.
  Future<ToolResult> execute(String name, Map<String, dynamic> input) async {
    final reg = _tools[name];
    if (reg == null) {
      return ToolResult.error('Unknown tool: $name');
    }
    if (!reg.enabled) {
      return ToolResult.error('Tool "$name" is currently disabled');
    }
    if (reg.restricted) {
      return ToolResult.error(
        'Tool "$name" is restricted (plan mode may be active)',
      );
    }
    if (!reg.tool.isAvailable) {
      return ToolResult.error('Tool "$name" is not available on this platform');
    }

    // Validate input.
    final validation = reg.tool.validateInput(input);
    if (!validation.isValid) {
      return ToolResult.error(validation.error!);
    }

    // Pre-hooks.
    for (final hook in _preHooks) {
      final proceed = await hook(name, input);
      if (!proceed) {
        return ToolResult.error('Execution blocked by pre-hook');
      }
    }

    // Execute with timing.
    final stopwatch = Stopwatch()..start();
    ToolResult result;
    try {
      result = await reg.tool.execute(input);
    } catch (e) {
      result = ToolResult.error('Tool "$name" error: $e');
    }
    stopwatch.stop();

    // Record stats.
    reg.recordExecution(stopwatch.elapsed);

    // Emit event.
    final event = ToolExecutionEvent(
      toolName: name,
      category: reg.category,
      duration: stopwatch.elapsed,
      isError: result.isError,
      timestamp: DateTime.now(),
    );
    _executionController.add(event);

    // Post-hooks.
    for (final hook in _postHooks) {
      hook(event);
    }

    return result;
  }

  // ── Enable / Disable / Restrict ──────────────────────────────────────────

  /// Enable a tool.
  void enable(String name) {
    _tools[name]?.enabled = true;
  }

  /// Disable a tool.
  void disable(String name) {
    _tools[name]?.enabled = false;
  }

  /// Restrict a tool (e.g. during plan mode).
  void restrict(String name) {
    _tools[name]?.restricted = true;
  }

  /// Unrestrict a tool.
  void unrestrict(String name) {
    _tools[name]?.restricted = false;
  }

  /// Restrict all tools except those in [allowed].
  void restrictAllExcept(Set<String> allowed) {
    for (final reg in _tools.values) {
      reg.restricted = !allowed.contains(reg.name);
    }
  }

  /// Unrestrict all tools.
  void unrestrictAll() {
    for (final reg in _tools.values) {
      reg.restricted = false;
    }
  }

  // ── Schema Access ────────────────────────────────────────────────────────

  /// Get the input schema for a specific tool.
  Map<String, dynamic>? getSchema(String name) =>
      _tools[name]?.tool.inputSchema;

  /// Get all tool schemas keyed by name.
  Map<String, Map<String, dynamic>> getAllSchemas() => {
    for (final entry in _tools.entries) entry.key: entry.value.tool.inputSchema,
  };

  /// Validate input for a named tool against its schema.
  ValidationResult validateInput(String name, Map<String, dynamic> input) {
    final reg = _tools[name];
    if (reg == null) {
      return ValidationResult.invalid('Unknown tool: $name');
    }
    return reg.tool.validateInput(input);
  }

  // ── Stats ────────────────────────────────────────────────────────────────

  /// Get stats for a specific tool.
  ToolStats? getStats(String name) {
    final reg = _tools[name];
    if (reg == null) return null;
    return ToolStats(
      name: reg.name,
      category: reg.category,
      executionCount: reg.executionCount,
      avgDurationMs: reg.avgDurationMs,
      lastExecutedAt: reg.lastExecutedAt,
      enabled: reg.enabled,
      restricted: reg.restricted,
    );
  }

  /// Get stats for all tools.
  List<ToolStats> getAllStats() => _tools.values
      .map(
        (r) => ToolStats(
          name: r.name,
          category: r.category,
          executionCount: r.executionCount,
          avgDurationMs: r.avgDurationMs,
          lastExecutedAt: r.lastExecutedAt,
          enabled: r.enabled,
          restricted: r.restricted,
        ),
      )
      .toList();

  // ── Fuzzy Search ─────────────────────────────────────────────────────────

  /// Find tools whose names are similar to [query] (case-insensitive prefix
  /// and substring matching).
  List<ToolRegistration> findSimilar(String query) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();

    // Exact match first.
    final exact = _tools[query];
    if (exact != null) return [exact];

    // Prefix matches.
    final prefixMatches = _tools.values
        .where((r) => r.name.toLowerCase().startsWith(q))
        .toList();
    if (prefixMatches.isNotEmpty) return prefixMatches;

    // Substring matches.
    final substringMatches = _tools.values
        .where((r) => r.name.toLowerCase().contains(q))
        .toList();
    if (substringMatches.isNotEmpty) return substringMatches;

    // Levenshtein-based fuzzy (simple edit distance for short names).
    final scored = <(ToolRegistration, int)>[];
    for (final reg in _tools.values) {
      final dist = _editDistance(q, reg.name.toLowerCase());
      if (dist <= 3) {
        scored.add((reg, dist));
      }
    }
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    return scored.map((e) => e.$1).toList();
  }

  /// Simple Levenshtein edit distance.
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final m = a.length;
    final n = b.length;
    var prev = List.generate(n + 1, (j) => j);
    var curr = List.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1, // deletion
          curr[j - 1] + 1, // insertion
          prev[j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  // ── Hooks ────────────────────────────────────────────────────────────────

  /// Add a pre-execution hook. Return false from the hook to block execution.
  void addPreHook(
    Future<bool> Function(String name, Map<String, dynamic> input) hook,
  ) {
    _preHooks.add(hook);
  }

  /// Add a post-execution hook.
  void addPostHook(void Function(ToolExecutionEvent event) hook) {
    _postHooks.add(hook);
  }

  // ── Builtin Registration ─────────────────────────────────────────────────

  /// Register all 18+ built-in tools.
  ///
  /// Call this during app initialization. Tools are registered with their
  /// appropriate categories. Pass tool instances for tools that require
  /// constructor parameters (e.g., BashTool with a working directory).
  void registerBuiltinTools({
    Tool? bashTool,
    Tool? fileReadTool,
    Tool? fileWriteTool,
    Tool? fileEditTool,
    Tool? globTool,
    Tool? grepTool,
    Tool? agentTool,
    Tool? sendMessageTool,
    Tool? todoWriteTool,
    Tool? taskOutputTool,
    Tool? toolSearchTool,
    Tool? webFetchTool,
    Tool? webSearchTool,
    Tool? notebookEditTool,
    Tool? skillTool,
    Tool? enterPlanModeTool,
    Tool? exitPlanModeTool,
    Tool? powerShellTool,
  }) {
    // File tools.
    if (fileReadTool != null) {
      register(fileReadTool, category: ToolCategory.file);
    }
    if (fileWriteTool != null) {
      register(fileWriteTool, category: ToolCategory.file);
    }
    if (fileEditTool != null) {
      register(fileEditTool, category: ToolCategory.file);
    }

    // Search tools.
    if (globTool != null) register(globTool, category: ToolCategory.search);
    if (grepTool != null) register(grepTool, category: ToolCategory.search);
    if (toolSearchTool != null) {
      register(toolSearchTool, category: ToolCategory.search);
    }

    // System tools.
    if (bashTool != null) register(bashTool, category: ToolCategory.system);
    if (powerShellTool != null) {
      register(powerShellTool, category: ToolCategory.system);
    }

    // Web tools.
    if (webFetchTool != null) {
      register(webFetchTool, category: ToolCategory.web);
    }
    if (webSearchTool != null) {
      register(webSearchTool, category: ToolCategory.web);
    }

    // Agent tools.
    if (agentTool != null) register(agentTool, category: ToolCategory.agent);
    if (sendMessageTool != null) {
      register(sendMessageTool, category: ToolCategory.agent);
    }
    if (taskOutputTool != null) {
      register(taskOutputTool, category: ToolCategory.agent);
    }

    // Editor tools.
    if (notebookEditTool != null) {
      register(notebookEditTool, category: ToolCategory.editor);
    }
    if (todoWriteTool != null) {
      register(todoWriteTool, category: ToolCategory.editor);
    }
    if (skillTool != null) register(skillTool, category: ToolCategory.editor);

    // Plan mode tools.
    if (enterPlanModeTool != null) {
      register(enterPlanModeTool, category: ToolCategory.system);
    }
    if (exitPlanModeTool != null) {
      register(exitPlanModeTool, category: ToolCategory.system);
    }
  }

  /// Register tools from an MCP server.
  ///
  /// Each MCP tool is wrapped in a [ToolRegistration] with
  /// [ToolCategory.mcp] and the server info attached.
  void registerMcpTools(List<Tool> mcpTools) {
    for (final tool in mcpTools) {
      register(tool, category: ToolCategory.mcp);
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  /// Remove all registered tools.
  void clear() {
    _tools.clear();
  }

  /// Dispose of internal resources.
  void dispose() {
    _executionController.close();
  }
}
