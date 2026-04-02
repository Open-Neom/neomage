/// Schema definition for a tool, matching Anthropic's tool format.
class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

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
