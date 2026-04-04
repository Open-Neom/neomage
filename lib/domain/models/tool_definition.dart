/// Schema definition for a tool, matching Anthropic's tool format.
class ToolDefinition {
  /// Unique name identifying this tool.
  final String name;

  /// Human-readable description of what the tool does.
  final String description;

  /// JSON Schema describing the tool's input parameters.
  final Map<String, dynamic> inputSchema;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  /// Convert to Anthropic API tool format.
  Map<String, dynamic> toApiMap() => {
    'name': name,
    'description': description,
    'input_schema': inputSchema,
  };

  /// Convert to OpenAI function format.
  Map<String, dynamic> toOpenAiMap() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };
}
