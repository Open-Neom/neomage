/// A provider-agnostic representation of an AI model response message.
///
/// Normalizes the different response formats from Anthropic, OpenAI, Gemini,
/// and other providers into a single consistent structure.
class NormalizedMessage {
  /// The role: 'user', 'assistant', 'system', or 'tool'.
  final String role;

  /// Extracted text content parts from the response.
  final List<String> textParts;

  /// Extracted thinking/reasoning parts (e.g., Anthropic's extended thinking).
  final List<String> thinkingParts;

  /// Tool call blocks from the response.
  final List<Map<String, dynamic>> toolCalls;

  /// The provider that generated this message, if known.
  /// Values: 'anthropic', 'openai', 'gemini', etc.
  final String? rawProvider;

  const NormalizedMessage({
    required this.role,
    this.textParts = const [],
    this.thinkingParts = const [],
    this.toolCalls = const [],
    this.rawProvider,
  });

  /// Returns all text parts joined as a single string.
  String get fullText => textParts.join('\n');

  /// Whether this message contains any thinking blocks.
  bool get hasThinking => thinkingParts.isNotEmpty;

  /// Whether this message contains any tool calls.
  bool get hasToolCalls => toolCalls.isNotEmpty;

  @override
  String toString() =>
      'NormalizedMessage($role, ${textParts.length} text, '
      '${thinkingParts.length} thinking, ${toolCalls.length} tools'
      '${rawProvider != null ? ', $rawProvider' : ''})';
}
