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
  static const Set<String> _blockedToolKeys = <String>{
    '__proto__',
    'constructor',
    'prototype',
  };

  static final RegExp _gemmaChannelRe = RegExp(
    r'<\|channel>\s*thought\s*\n?([\s\S]*?)<channel\|>',
    caseSensitive: false,
  );
  static final RegExp _unclosedGemmaChannelRe = RegExp(
    r'<\|channel>\s*thought\s*\n?([\s\S]*)$',
    caseSensitive: false,
  );
  static final RegExp _thinkBlockRe = RegExp(
    r'<\s*(think|thinking|thought)\b[^>]*>([\s\S]*?)<\s*/\s*\1\s*>',
    caseSensitive: false,
  );
  static final RegExp _unclosedThinkRe = RegExp(
    r'<\s*(?:think|thinking|thought)\b[^>]*>([\s\S]*)$',
    caseSensitive: false,
  );
  static final RegExp _residualControlTokensRe = RegExp(
    r'<\|/?turn\|>|<\|channel>|<channel\|>|<\|eot_id\|>|<(?:start|end)_of_turn>|<\|im_(?:start|end)\|>',
    caseSensitive: false,
  );

  static void _ingestTextWithReasoning(
    String raw,
    List<String> textParts,
    List<String> thinkingParts,
  ) {
    if (raw.isEmpty) return;
    var work = raw;

    for (final m in _gemmaChannelRe.allMatches(work)) {
      final t = (m.group(1) ?? '').trim();
      if (t.isNotEmpty) thinkingParts.add(t);
    }
    work = work.replaceAll(_gemmaChannelRe, '');

    final unclosedGemma = _unclosedGemmaChannelRe.firstMatch(work);
    if (unclosedGemma != null) {
      final t = (unclosedGemma.group(1) ?? '').trim();
      if (t.isNotEmpty) thinkingParts.add(t);
      work = work.substring(0, unclosedGemma.start);
    }

    for (final m in _thinkBlockRe.allMatches(work)) {
      final t = (m.group(2) ?? '').trim();
      if (t.isNotEmpty) thinkingParts.add(t);
    }
    work = work.replaceAll(_thinkBlockRe, '');

    final unclosedThink = _unclosedThinkRe.firstMatch(work);
    if (unclosedThink != null) {
      final t = (unclosedThink.group(1) ?? '').trim();
      if (t.isNotEmpty) thinkingParts.add(t);
      work = work.substring(0, unclosedThink.start);
    }

    work = work.replaceAll(_residualControlTokensRe, '');
    if (work.isNotEmpty) {
      textParts.add(work);
    }
  }

  static Map<String, dynamic> _sanitizeToolMap(
    Map<dynamic, dynamic> raw, {
    int depth = 0,
  }) {
    if (depth > 24) return <String, dynamic>{};
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key == null) return;
      final ks = key.toString();
      if (_blockedToolKeys.contains(ks)) return;
      if (value is Map) {
        out[ks] = _sanitizeToolMap(value, depth: depth + 1);
      } else if (value is List) {
        out[ks] = value
            .map((e) => e is Map ? _sanitizeToolMap(e, depth: depth + 1) : e)
            .toList();
      } else {
        out[ks] = value;
      }
    });
    return out;
  }

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

  NormalizedMessage _normalizeAnthropic(Map<String, dynamic> response) {
    final role = response['role']?.toString() ?? 'assistant';
    final content = response['content'];

    final textParts = <String>[];
    final thinkingParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    if (content is List) {
      for (final block in content) {
        if (block is! Map) continue;
        final type = block['type']?.toString();

        switch (type) {
          case 'text':
            final text = block['text']?.toString();
            if (text != null && text.isNotEmpty) {
              _ingestTextWithReasoning(text, textParts, thinkingParts);
            }
            break;
          case 'thinking':
            final thinking = block['thinking']?.toString();
            if (thinking != null && thinking.isNotEmpty) {
              thinkingParts.add(thinking);
            }
            break;
          case 'tool_use':
            toolCalls.add(_sanitizeToolMap(block));
            break;
        }
      }
    } else if (content is String) {
      _ingestTextWithReasoning(content, textParts, thinkingParts);
    }

    return NormalizedMessage(
      role: role,
      textParts: textParts,
      thinkingParts: thinkingParts,
      toolCalls: toolCalls,
      rawProvider: 'anthropic',
    );
  }

  NormalizedMessage _normalizeOpenAI(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      return _normalizeFallback(response, 'openai');
    }

    final firstChoice = choices[0];
    if (firstChoice is! Map) {
      return _normalizeFallback(response, 'openai');
    }

    final message = firstChoice['message'];
    if (message is! Map) {
      return _normalizeFallback(response, 'openai');
    }

    final role = message['role']?.toString() ?? 'assistant';
    final textParts = <String>[];
    final thinkingParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    final reasoning =
        message['reasoning_content'] ?? message['reasoning'];
    if (reasoning is String && reasoning.trim().isNotEmpty) {
      thinkingParts.add(reasoning.trim());
    }

    final content = message['content'];
    if (content is String && content.isNotEmpty) {
      _ingestTextWithReasoning(content, textParts, thinkingParts);
    }

    final tools = message['tool_calls'];
    if (tools is List) {
      for (final tool in tools) {
        if (tool is Map) {
          toolCalls.add(_sanitizeToolMap(tool));
        }
      }
    }

    return NormalizedMessage(
      role: role,
      textParts: textParts,
      thinkingParts: thinkingParts,
      toolCalls: toolCalls,
      rawProvider: 'openai',
    );
  }

  NormalizedMessage _normalizeGemini(Map<String, dynamic> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return _normalizeFallback(response, 'gemini');
    }

    final firstCandidate = candidates[0];
    if (firstCandidate is! Map) {
      return _normalizeFallback(response, 'gemini');
    }

    final content = firstCandidate['content'];
    if (content is! Map) {
      return _normalizeFallback(response, 'gemini');
    }

    final role = content['role']?.toString() ?? 'model';
    final normalizedRole = role == 'model' ? 'assistant' : role;
    final textParts = <String>[];
    final thinkingParts = <String>[];
    final toolCalls = <Map<String, dynamic>>[];

    final parts = content['parts'];
    if (parts is List) {
      for (final part in parts) {
        if (part is! Map) continue;

        final text = part['text']?.toString();
        if (part['thought'] == true) {
          if (text != null && text.trim().isNotEmpty) {
            thinkingParts.add(text.trim());
          }
          continue;
        }
        if (text != null && text.isNotEmpty) {
          _ingestTextWithReasoning(text, textParts, thinkingParts);
        }

        final functionCall = part['functionCall'];
        if (functionCall is Map) {
          toolCalls.add(_sanitizeToolMap(functionCall));
        }
      }
    }

    return NormalizedMessage(
      role: normalizedRole,
      textParts: textParts,
      thinkingParts: thinkingParts,
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
    final thinkingParts = <String>[];

    // Try common keys.
    for (final key in ['content', 'text', 'message', 'output', 'response']) {
      final value = response[key];
      if (value is String && value.isNotEmpty) {
        _ingestTextWithReasoning(value, textParts, thinkingParts);
        break;
      }
    }

    return NormalizedMessage(
      role: response['role']?.toString() ?? 'assistant',
      textParts: textParts,
      thinkingParts: thinkingParts,
      rawProvider: provider,
    );
  }
}
