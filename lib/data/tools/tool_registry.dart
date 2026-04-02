import '../../domain/models/tool_definition.dart';
import 'tool.dart';

/// Registry of available tools.
/// Mirrors openclaude's tool registration system.
class ToolRegistry {
  final Map<String, Tool> _tools = {};

  /// Register a tool.
  void register(Tool tool) {
    _tools[tool.name] = tool;
  }

  /// Unregister a tool.
  void unregister(String name) {
    _tools.remove(name);
  }

  /// Get a tool by name.
  Tool? get(String name) => _tools[name];

  /// All registered tools.
  Iterable<Tool> get all => _tools.values;

  /// All available tools for the current platform.
  Iterable<Tool> get available => _tools.values.where((t) => t.isAvailable);

  /// Tool definitions for API calls.
  List<ToolDefinition> get definitions =>
      available.map((t) => t.definition).toList();

  /// Execute a tool by name.
  Future<ToolResult> execute(String name, Map<String, dynamic> input) async {
    final tool = _tools[name];
    if (tool == null) {
      return ToolResult.error('Unknown tool: $name');
    }
    if (!tool.isAvailable) {
      return ToolResult.error('Tool "$name" is not available on this platform');
    }
    try {
      return await tool.execute(input);
    } catch (e) {
      return ToolResult.error('Tool "$name" error: $e');
    }
  }
}
