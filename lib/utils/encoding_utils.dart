// Encoding utilities — port of neom_claw encoding/escaping helpers.
// Token estimation, text encoding, content escaping.

import 'dart:convert';

/// Estimate token count from text.
/// Uses the ~4 chars/token heuristic (accurate within ~15% for English).
int estimateTokens(String text) => (text.length / 4).ceil();

/// Estimate tokens for a list of messages.
int estimateMessageTokens(List<Map<String, dynamic>> messages) {
  var total = 0;
  for (final msg in messages) {
    // Base overhead per message
    total += 4;
    final content = msg['content'];
    if (content is String) {
      total += estimateTokens(content);
    } else if (content is List) {
      for (final block in content) {
        if (block is Map<String, dynamic>) {
          if (block['type'] == 'text') {
            total += estimateTokens(block['text'] as String? ?? '');
          } else if (block['type'] == 'tool_use') {
            total += estimateTokens(jsonEncode(block['input']));
          } else if (block['type'] == 'tool_result') {
            total += estimateTokens(block['content'] as String? ?? '');
          }
        }
      }
    }
  }
  return total;
}

/// Escape text for XML tag content.
String escapeXml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Unescape XML entities.
String unescapeXml(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

/// Escape diff tokens — the diff library has issues with & and $.
String escapeDiffTokens(String text) {
  return text.replaceAll('&', '\u0000&').replaceAll('\$', '\u0000\$');
}

/// Unescape diff tokens.
String unescapeDiffTokens(String text) {
  return text.replaceAll('\u0000&', '&').replaceAll('\u0000\$', '\$');
}

/// Truncate text to a maximum length with ellipsis.
String truncate(String text, int maxLength, {String suffix = '...'}) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength - suffix.length)}$suffix';
}

/// Truncate text to a maximum number of lines.
String truncateLines(String text, int maxLines, {String suffix = '\n...'}) {
  final lines = text.split('\n');
  if (lines.length <= maxLines) return text;
  return '${lines.take(maxLines).join('\n')}$suffix';
}

/// Wrap text in an XML tag.
String xmlTag(String tag, String content, {Map<String, String>? attrs}) {
  final attrStr = attrs?.entries.map((e) => ' ${e.key}="${escapeXml(e.value)}"').join('') ?? '';
  return '<$tag$attrStr>\n$content\n</$tag>';
}

/// Parse content from an XML tag.
String? parseXmlTag(String text, String tag) {
  final openTag = '<$tag>';
  final closeTag = '</$tag>';
  final start = text.indexOf(openTag);
  if (start == -1) return null;
  final contentStart = start + openTag.length;
  final end = text.indexOf(closeTag, contentStart);
  if (end == -1) return null;
  return text.substring(contentStart, end).trim();
}

/// Base64 encode string.
String base64Encode(String text) => base64.encode(utf8.encode(text));

/// Base64 decode string.
String base64Decode(String encoded) =>
    utf8.decode(base64.decode(encoded));

/// Sanitize a filename (remove unsafe characters).
String sanitizeFilename(String name) {
  return name
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^\.+'), '');
}

/// Format bytes as human-readable string.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Format duration as human-readable string.
String formatDuration(Duration duration) {
  if (duration.inSeconds < 1) return '${duration.inMilliseconds}ms';
  if (duration.inMinutes < 1) return '${duration.inSeconds}s';
  if (duration.inHours < 1) {
    return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  }
  return '${duration.inHours}h ${duration.inMinutes % 60}m';
}

/// Generate a simple hash for cache keys.
int simpleHash(String text) {
  var hash = 0;
  for (var i = 0; i < text.length; i++) {
    hash = ((hash << 5) - hash + text.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return hash;
}

/// Check if text likely contains markdown syntax.
bool containsMarkdown(String text) {
  if (text.length > 500) {
    return RegExp(r'[*_`#\[>\-|~]|^\d+\.', multiLine: true)
        .hasMatch(text.substring(0, 500));
  }
  return RegExp(r'[*_`#\[>\-|~]|^\d+\.', multiLine: true).hasMatch(text);
}
