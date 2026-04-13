import '../../domain/models/normalized_message.dart';
import '../../domain/services/message_normalizer_service.dart';

/// Concrete implementation of [MessageNormalizerService].
///
/// Handles response format differences across AI providers:
/// - **Anthropic**: content blocks with `type: 'text'`, `'thinking'`, `'tool_use'`
/// - **OpenAI**: `choices[0].message.content` + `tool_calls[]`
/// - **Gemini**: `candidates[0].content.parts[{text: '...'}]`
/// - **Fallback**: treats the response as plain text
class MessageNormalizer implements MessageNormalizerService {
  @override
  NormalizedMessage normalize(
    Map<String, dynamic> providerResponse,
    String provider,
  ) {
    switch (provider.toLowerCase()) {
      case 'anthropic':
        return _normalizeAnthropic(providerResponse);
      case 'openai':
        return _normalizeOpenAI(providerResponse);
      case 'gemini':
        return _normalizeGemini(providerResponse);
      default:
        return _normalizeFallback(providerResponse, provider);
    }
  }

  /// Anthropic format:
  /// ```json
  /// {
  ///   "role": "assistant",
  ///   "content": [
  ///     {"type": "text", "text": "..."},
  ///     {"type": "thinking", "thinking": "..."},
  ///     {"type": "tool_use", "id": "...", "name": "...", "input": {...}}
  ///   ]
  /// }
  /// ```
  NormalizedMessage _normalizeAnthropic(Map<String, dynamic> response) {
    final role = response['role']?.toString() ?? 'assistant';
    final content = response['content'];

    final textParts = <String>[];
    final thinkingParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    if (content is List) {
      for (final block in content) {
        if (block is! Map<String, dynamic>) continue;
        final type = block['type']?.toString();

        switch (type) {
          case 'text':
            final text = block['text']?.toString();
            if (text != null && text.isNotEmpty) textParts.add(text);
            break;
          case 'thinking':
            final thinking = block['thinking']?.toString();
            if (thinking != null && thinking.isNotEmpty) {
              thinkingParts.add(thinking);
            }
            break;
          case 'tool_use':
            toolCalls.add(Map<String, dynamic>.from(block));
            break;
        }
      }
    } else if (content is String) {
      textParts.add(content);
    }

    return NormalizedMessage(
      role: role,
      textParts: textParts,
      thinkingParts: thinkingParts,
      toolCalls: toolCalls,
      rawProvider: 'anthropic',
    );
  }

  /// OpenAI format:
  /// ```json
  /// {
  ///   "choices": [{
  ///     "message": {
  ///       "role": "assistant",
  ///       "content": "...",
  ///       "tool_calls": [{"id": "...", "function": {"name": "...", "arguments": "..."}}]
  ///     }
  ///   }]
  /// }
  /// ```
  NormalizedMessage _normalizeOpenAI(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      return _normalizeFallback(response, 'openai');
    }

    final firstChoice = choices[0];
    if (firstChoice is! Map<String, dynamic>) {
      return _normalizeFallback(response, 'openai');
    }

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      return _normalizeFallback(response, 'openai');
    }

    final role = message['role']?.toString() ?? 'assistant';
    final textParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    final content = message['content'];
    if (content is String && content.isNotEmpty) {
      textParts.add(content);
    }

    final tools = message['tool_calls'];
    if (tools is List) {
      for (final tool in tools) {
        if (tool is Map<String, dynamic>) {
          toolCalls.add(Map<String, dynamic>.from(tool));
        }
      }
    }

    return NormalizedMessage(
      role: role,
      textParts: textParts,
      toolCalls: toolCalls,
      rawProvider: 'openai',
    );
  }

  /// Gemini format:
  /// ```json
  /// {
  ///   "candidates": [{
  ///     "content": {
  ///       "role": "model",
  ///       "parts": [{"text": "..."}]
  ///     }
  ///   }]
  /// }
  /// ```
  NormalizedMessage _normalizeGemini(Map<String, dynamic> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return _normalizeFallback(response, 'gemini');
    }

    final firstCandidate = candidates[0];
    if (firstCandidate is! Map<String, dynamic>) {
      return _normalizeFallback(response, 'gemini');
    }

    final content = firstCandidate['content'];
    if (content is! Map<String, dynamic>) {
      return _normalizeFallback(response, 'gemini');
    }

    final role = content['role']?.toString() ?? 'model';
    final normalizedRole = role == 'model' ? 'assistant' : role;
    final textParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    final parts = content['parts'];
    if (parts is List) {
      for (final part in parts) {
        if (part is! Map<String, dynamic>) continue;

        final text = part['text']?.toString();
        if (text != null && text.isNotEmpty) {
          textParts.add(text);
        }

        final functionCall = part['functionCall'];
        if (functionCall is Map<String, dynamic>) {
          toolCalls.add(Map<String, dynamic>.from(functionCall));
        }
      }
    }

    return NormalizedMessage(
      role: normalizedRole,
      textParts: textParts,
      toolCalls: toolCalls,
      rawProvider: 'gemini',
    );
  }

  /// Fallback: try to extract any text-like content from the response.
  NormalizedMessage _normalizeFallback(
    Map<String, dynamic> response,
    String provider,
  ) {
    final textParts = <String>[];

    // Try common keys.
    for (final key in ['content', 'text', 'message', 'output', 'response']) {
      final value = response[key];
      if (value is String && value.isNotEmpty) {
        textParts.add(value);
        break;
      }
    }

    return NormalizedMessage(
      role: response['role']?.toString() ?? 'assistant',
      textParts: textParts,
      rawProvider: provider,
    );
  }
}
