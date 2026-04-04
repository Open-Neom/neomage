// Port of openneomclaw format.ts + truncate.ts + treeify.ts + json.ts +
// frontmatterParser.ts
//
// Formatting, truncation, tree rendering, JSON/JSONL parsing, and
// frontmatter parsing utilities for the neom_claw package.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

import 'package:characters/characters.dart';

// ---------------------------------------------------------------------------
// format.ts  --  pure display formatters
// ---------------------------------------------------------------------------

/// Formats a byte count to a human-readable string (KB, MB, GB).
/// Example: `formatFileSize(1536)` returns `"1.5KB"`.
String formatFileSize(int sizeInBytes) {
  final kb = sizeInBytes / 1024;
  if (kb < 1) return '$sizeInBytes bytes';
  if (kb < 1024) {
    return '${_trimTrailingZero(kb.toStringAsFixed(1))}KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${_trimTrailingZero(mb.toStringAsFixed(1))}MB';
  }
  final gb = mb / 1024;
  return '${_trimTrailingZero(gb.toStringAsFixed(1))}GB';
}

String _trimTrailingZero(String s) => s.replaceFirst(RegExp(r'\.0$'), '');

/// Formats milliseconds as seconds with 1 decimal place.
/// Example: `formatSecondsShort(1234)` returns `"1.2s"`.
String formatSecondsShort(int ms) {
  return '${(ms / 1000).toStringAsFixed(1)}s';
}

/// Formats a duration in milliseconds to a human-readable string.
String formatDuration(
  int ms, {
  bool hideTrailingZeros = false,
  bool mostSignificantOnly = false,
}) {
  if (ms < 60000) {
    if (ms == 0) return '0s';
    if (ms < 1) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms ~/ 1000}s';
  }

  var days = ms ~/ 86400000;
  var hours = (ms % 86400000) ~/ 3600000;
  var minutes = (ms % 3600000) ~/ 60000;
  var seconds = ((ms % 60000) / 1000).round();

  // Handle rounding carry-over
  if (seconds == 60) {
    seconds = 0;
    minutes++;
  }
  if (minutes == 60) {
    minutes = 0;
    hours++;
  }
  if (hours == 24) {
    hours = 0;
    days++;
  }

  if (mostSignificantOnly) {
    if (days > 0) return '${days}d';
    if (hours > 0) return '${hours}h';
    if (minutes > 0) return '${minutes}m';
    return '${seconds}s';
  }

  if (days > 0) {
    if (hideTrailingZeros && hours == 0 && minutes == 0) return '${days}d';
    if (hideTrailingZeros && minutes == 0) return '${days}d ${hours}h';
    return '${days}d ${hours}h ${minutes}m';
  }
  if (hours > 0) {
    if (hideTrailingZeros && minutes == 0 && seconds == 0) return '${hours}h';
    if (hideTrailingZeros && seconds == 0) return '${hours}h ${minutes}m';
    return '${hours}h ${minutes}m ${seconds}s';
  }
  if (minutes > 0) {
    if (hideTrailingZeros && seconds == 0) return '${minutes}m';
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}

/// Formats a number using compact notation.
/// Example: `formatNumber(1321)` returns `"1.3k"`.
String formatNumber(int number) {
  if (number < 1000) return '$number';
  if (number < 1000000) {
    final k = number / 1000;
    return '${k.toStringAsFixed(1)}k';
  }
  if (number < 1000000000) {
    final m = number / 1000000;
    return '${m.toStringAsFixed(1)}m';
  }
  final b = number / 1000000000;
  return '${b.toStringAsFixed(1)}b';
}

/// Formats a token count, removing trailing `.0`.
String formatTokens(int count) {
  return formatNumber(count).replaceFirst('.0', '');
}

/// Relative time style.
enum RelativeTimeStyle { long, short, narrow }

/// Format a date as a relative time string.
String formatRelativeTime(
  DateTime date, {
  RelativeTimeStyle style = RelativeTimeStyle.narrow,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final diffInMs = date.millisecondsSinceEpoch - reference.millisecondsSinceEpoch;
  final diffInSeconds = diffInMs ~/ 1000; // truncate toward zero

  final intervals = <({String unit, int seconds, String shortUnit})>[
    (unit: 'year', seconds: 31536000, shortUnit: 'y'),
    (unit: 'month', seconds: 2592000, shortUnit: 'mo'),
    (unit: 'week', seconds: 604800, shortUnit: 'w'),
    (unit: 'day', seconds: 86400, shortUnit: 'd'),
    (unit: 'hour', seconds: 3600, shortUnit: 'h'),
    (unit: 'minute', seconds: 60, shortUnit: 'm'),
    (unit: 'second', seconds: 1, shortUnit: 's'),
  ];

  for (final interval in intervals) {
    if (diffInSeconds.abs() >= interval.seconds) {
      final value = diffInSeconds ~/ interval.seconds;
      if (style == RelativeTimeStyle.narrow) {
        return diffInSeconds < 0
            ? '${value.abs()}${interval.shortUnit} ago'
            : 'in $value${interval.shortUnit}';
      }
      // Long/short style
      final absValue = value.abs();
      final unitLabel = absValue == 1 ? interval.unit : '${interval.unit}s';
      return diffInSeconds < 0
          ? '$absValue $unitLabel ago'
          : 'in $absValue $unitLabel';
    }
  }

  if (style == RelativeTimeStyle.narrow) {
    return diffInSeconds <= 0 ? '0s ago' : 'in 0s';
  }
  return diffInSeconds <= 0 ? '0 seconds ago' : 'in 0 seconds';
}

/// Format a past date as relative time ago.
String formatRelativeTimeAgo(
  DateTime date, {
  RelativeTimeStyle style = RelativeTimeStyle.narrow,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  if (date.isAfter(reference)) {
    return formatRelativeTime(date, style: style, now: reference);
  }
  return formatRelativeTime(date, style: style, now: reference);
}

/// Formats log metadata for display.
String formatLogMetadata({
  required DateTime modified,
  required int messageCount,
  int? fileSize,
  String? gitBranch,
  String? tag,
  String? agentSetting,
  int? prNumber,
  String? prRepository,
}) {
  final sizeOrCount =
      fileSize != null ? formatFileSize(fileSize) : '$messageCount messages';
  final parts = <String>[
    formatRelativeTimeAgo(modified, style: RelativeTimeStyle.short),
    ?gitBranch,
    sizeOrCount,
    if (tag != null) '#$tag',
    if (agentSetting != null) '@$agentSetting',
    if (prNumber != null)
      prRepository != null ? '$prRepository#$prNumber' : '#$prNumber',
  ];
  return parts.join(' \u00b7 '); // middle dot separator
}

/// Formats a reset timestamp for display.
String? formatResetTime(
  int? timestampInSeconds, {
  bool showTimezone = false,
  bool showTime = true,
}) {
  if (timestampInSeconds == null || timestampInSeconds == 0) return null;

  final date = DateTime.fromMillisecondsSinceEpoch(timestampInSeconds * 1000);
  final now = DateTime.now();
  final hoursUntilReset =
      (date.millisecondsSinceEpoch - now.millisecondsSinceEpoch) /
          (1000 * 60 * 60);

  if (hoursUntilReset > 24) {
    final buf = StringBuffer();
    buf.write('${_monthAbbr(date.month)} ${date.day}');
    if (date.year != now.year) buf.write(', ${date.year}');
    if (showTime) {
      buf.write(' ${_formatTime12(date)}');
    }
    if (showTimezone) buf.write(' (${date.timeZoneName})');
    return buf.toString();
  }

  final buf = StringBuffer(_formatTime12(date));
  if (showTimezone) buf.write(' (${date.timeZoneName})');
  return buf.toString();
}

String _monthAbbr(int month) {
  const names = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[month];
}

String _formatTime12(DateTime date) {
  final hour = date.hour;
  final minute = date.minute;
  final period = hour >= 12 ? 'pm' : 'am';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  if (minute == 0) return '$displayHour$period';
  return '$displayHour:${minute.toString().padLeft(2, '0')}$period';
}

/// Format a reset time from an ISO 8601 string.
String formatResetText(
  String resetsAt, {
  bool showTimezone = false,
  bool showTime = true,
}) {
  final dt = DateTime.parse(resetsAt);
  return formatResetTime(
        dt.millisecondsSinceEpoch ~/ 1000,
        showTimezone: showTimezone,
        showTime: showTime,
      ) ??
      '';
}

// ---------------------------------------------------------------------------
// truncate.ts  --  width-aware truncation
// ---------------------------------------------------------------------------

/// Returns the visual width of a string (simple approximation).
/// For full CJK/emoji awareness, integrate a proper stringWidth package.
int stringWidth(String text) {
  // Simple: count characters. Replace with a proper grapheme-aware
  // width calculation when a suitable Dart package is available.
  var width = 0;
  for (final rune in text.runes) {
    if (rune > 0xFFFF) {
      width += 2; // Emoji / surrogate pair
    } else if (_isCJK(rune)) {
      width += 2;
    } else {
      width += 1;
    }
  }
  return width;
}

bool _isCJK(int rune) {
  return (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x20000 && rune <= 0x2A6DF) ||
      (rune >= 0x2A700 && rune <= 0x2B73F) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0xFE30 && rune <= 0xFE4F) ||
      (rune >= 0xFF00 && rune <= 0xFF60) ||
      (rune >= 0xFFE0 && rune <= 0xFFE6);
}

/// Truncates a file path in the middle to preserve directory context and filename.
String truncatePathMiddle(String path, int maxLength) {
  if (stringWidth(path) <= maxLength) return path;
  if (maxLength <= 0) return '\u2026';
  if (maxLength < 5) return truncateToWidth(path, maxLength);

  final lastSlash = path.lastIndexOf('/');
  final filename = lastSlash >= 0 ? path.substring(lastSlash) : path;
  final directory = lastSlash >= 0 ? path.substring(0, lastSlash) : '';
  final filenameWidth = stringWidth(filename);

  if (filenameWidth >= maxLength - 1) {
    return truncateStartToWidth(path, maxLength);
  }

  final availableForDir = maxLength - 1 - filenameWidth;
  if (availableForDir <= 0) {
    return truncateStartToWidth(filename, maxLength);
  }

  final truncatedDir = truncateToWidthNoEllipsis(directory, availableForDir);
  return '$truncatedDir\u2026$filename';
}

/// Truncates a string to fit within a maximum display width.
/// Appends '\u2026' (ellipsis) when truncation occurs.
String truncateToWidth(String text, int maxWidth) {
  if (stringWidth(text) <= maxWidth) return text;
  if (maxWidth <= 1) return '\u2026';

  var width = 0;
  final buf = StringBuffer();
  for (final char in text.characters) {
    final charWidth = stringWidth(char);
    if (width + charWidth > maxWidth - 1) break;
    buf.write(char);
    width += charWidth;
  }
  buf.write('\u2026');
  return buf.toString();
}

/// Truncates from the start of a string, keeping the tail end.
/// Prepends '\u2026' when truncation occurs.
String truncateStartToWidth(String text, int maxWidth) {
  if (stringWidth(text) <= maxWidth) return text;
  if (maxWidth <= 1) return '\u2026';

  final chars = text.characters.toList();
  var width = 0;
  var startIdx = chars.length;

  for (var i = chars.length - 1; i >= 0; i--) {
    final charWidth = stringWidth(chars[i]);
    if (width + charWidth > maxWidth - 1) break;
    width += charWidth;
    startIdx = i;
  }

  return '\u2026${chars.sublist(startIdx).join()}';
}

/// Truncates a string without appending an ellipsis.
String truncateToWidthNoEllipsis(String text, int maxWidth) {
  if (stringWidth(text) <= maxWidth) return text;
  if (maxWidth <= 0) return '';

  var width = 0;
  final buf = StringBuffer();
  for (final char in text.characters) {
    final charWidth = stringWidth(char);
    if (width + charWidth > maxWidth) break;
    buf.write(char);
    width += charWidth;
  }
  return buf.toString();
}

/// Truncates a string with optional single-line mode.
String truncate(String str, int maxWidth, {bool singleLine = false}) {
  var result = str;

  if (singleLine) {
    final firstNewline = str.indexOf('\n');
    if (firstNewline != -1) {
      result = str.substring(0, firstNewline);
      if (stringWidth(result) + 1 > maxWidth) {
        return truncateToWidth(result, maxWidth);
      }
      return '$result\u2026';
    }
  }

  if (stringWidth(result) <= maxWidth) return result;
  return truncateToWidth(result, maxWidth);
}

/// Wraps text to the given width, splitting on grapheme boundaries.
List<String> wrapText(String text, int width) {
  final lines = <String>[];
  var currentLine = StringBuffer();
  var currentWidth = 0;

  for (final char in text.characters) {
    final charWidth = stringWidth(char);
    if (currentWidth + charWidth <= width) {
      currentLine.write(char);
      currentWidth += charWidth;
    } else {
      if (currentLine.isNotEmpty) lines.add(currentLine.toString());
      currentLine = StringBuffer(char);
      currentWidth = charWidth;
    }
  }

  if (currentLine.isNotEmpty) lines.add(currentLine.toString());
  return lines;
}

// ---------------------------------------------------------------------------
// treeify.ts  --  tree rendering
// ---------------------------------------------------------------------------

/// A tree node can contain nested maps or string leaves.
typedef TreeNode = Map<String, dynamic>;

/// Options for tree rendering.
class TreeifyOptions {
  const TreeifyOptions({
    this.showValues = true,
    this.hideFunctions = false,
    this.useColors = false,
  });

  final bool showValues;
  final bool hideFunctions;
  final bool useColors;
}

// Box-drawing characters for the tree
const _treeBranch = '\u251C'; // '|'
const _treeLastBranch = '\u2514'; // '\'
const _treeLine = '\u2502'; // '|'
const _treeEmpty = ' ';

/// Render a tree node as a string.
String treeify(TreeNode obj, {TreeifyOptions options = const TreeifyOptions()}) {
  if (obj.isEmpty) return '(empty)';

  final lines = <String>[];
  final visited = <Object>{};

  void growBranch(
    dynamic node,
    String prefix,
    bool isLast, {
    int depth = 0,
  }) {
    if (node is String) {
      lines.add('$prefix$node');
      return;
    }

    if (node is! Map<String, dynamic>) {
      if (options.showValues) {
        lines.add('$prefix$node');
      }
      return;
    }

    if (visited.contains(node)) {
      lines.add('$prefix[Circular]');
      return;
    }
    visited.add(node);

    final keys = node.keys.toList();
    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      final value = node[key];
      final isLastKey = index == keys.length - 1;
      final nodePrefix = depth == 0 && index == 0 ? '' : prefix;

      final treeChar = isLastKey ? _treeLastBranch : _treeBranch;
      final formattedKey = key.trim().isEmpty ? '' : key;

      var line = '$nodePrefix$treeChar${formattedKey.isNotEmpty ? ' $formattedKey' : ''}';
      final shouldAddColon = key.trim().isNotEmpty;

      if (value is Map<String, dynamic> && visited.contains(value)) {
        lines.add(
          '$line${shouldAddColon ? ': ' : line.isNotEmpty ? ' ' : ''}[Circular]',
        );
      } else if (value is Map<String, dynamic>) {
        lines.add(line);
        final continuationChar = isLastKey ? _treeEmpty : _treeLine;
        final nextPrefix = '$nodePrefix$continuationChar ';
        growBranch(value, nextPrefix, isLastKey, depth: depth + 1);
      } else if (value is List) {
        lines.add(
          '$line${shouldAddColon ? ': ' : line.isNotEmpty ? ' ' : ''}[Array(${value.length})]',
        );
      } else if (options.showValues) {
        final valueStr = '$value';
        line +=
            '${shouldAddColon ? ': ' : line.isNotEmpty ? ' ' : ''}$valueStr';
        lines.add(line);
      } else {
        lines.add(line);
      }
    }
  }

  // Special case for single whitespace key
  if (obj.length == 1) {
    final key = obj.keys.first;
    if (key.trim().isEmpty && obj[key] is String) {
      return '$_treeLastBranch ${obj[key]}';
    }
  }

  growBranch(obj, '', true);
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// json.ts  --  JSON and JSONL parsing
// ---------------------------------------------------------------------------

/// Safely parse a JSON string, returning null on failure.
dynamic safeParseJSON(String? jsonStr, {bool shouldLogError = true}) {
  if (jsonStr == null || jsonStr.isEmpty) return null;
  try {
    final stripped = _stripBOM(jsonStr);
    return json.decode(stripped);
  } catch (e) {
    if (shouldLogError) {
      // In the Dart port, log to stderr as a placeholder
      stderr.writeln('safeParseJSON error: $e');
    }
    return null;
  }
}

/// Parse JSONL data from a string, skipping malformed lines.
List<T> parseJSONL<T>(String data) {
  final stripped = _stripBOM(data);
  final results = <T>[];
  var start = 0;

  while (start < stripped.length) {
    var end = stripped.indexOf('\n', start);
    if (end == -1) end = stripped.length;

    final line = stripped.substring(start, end).trim();
    start = end + 1;
    if (line.isEmpty) continue;

    try {
      results.add(json.decode(line) as T);
    } catch (_) {
      // Skip malformed lines
    }
  }
  return results;
}

/// Maximum bytes to read from the tail of a JSONL file.
const _maxJsonlReadBytes = 100 * 1024 * 1024;

/// Read and parse a JSONL file.
Future<List<T>> readJSONLFile<T>(String filePath) async {
  final file = File(filePath);
  final stat = await file.stat();
  if (stat.size <= _maxJsonlReadBytes) {
    final content = await file.readAsString();
    return parseJSONL<T>(content);
  }

  // For large files, read the tail
  final raf = await file.open(mode: FileMode.read);
  try {
    final offset = stat.size - _maxJsonlReadBytes;
    await raf.setPosition(offset);
    final bytes = await raf.read(_maxJsonlReadBytes);
    final content = utf8.decode(bytes, allowMalformed: true);

    // Skip the first partial line
    final newlineIndex = content.indexOf('\n');
    if (newlineIndex != -1 && newlineIndex < content.length - 1) {
      return parseJSONL<T>(content.substring(newlineIndex + 1));
    }
    return parseJSONL<T>(content);
  } finally {
    await raf.close();
  }
}

/// Add an item to a JSON array string, preserving formatting.
String addItemToJSONCArray(String content, dynamic newItem) {
  try {
    if (content.trim().isEmpty) {
      return const JsonEncoder.withIndent('    ').convert([newItem]);
    }

    final stripped = _stripBOM(content);
    final parsed = json.decode(stripped);

    if (parsed is List) {
      final copy = [...parsed, newItem];
      return const JsonEncoder.withIndent('    ').convert(copy);
    }

    return const JsonEncoder.withIndent('    ').convert([newItem]);
  } catch (e) {
    stderr.writeln('addItemToJSONCArray error: $e');
    return const JsonEncoder.withIndent('    ').convert([newItem]);
  }
}

/// Strip UTF-8 BOM from a string.
String _stripBOM(String s) {
  if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
    return s.substring(1);
  }
  return s;
}

// ---------------------------------------------------------------------------
// frontmatterParser.ts
// ---------------------------------------------------------------------------

/// Parsed frontmatter data (loosely typed).
typedef FrontmatterData = Map<String, dynamic>;

/// Result of parsing markdown with frontmatter.
class ParsedMarkdown {
  const ParsedMarkdown({
    required this.frontmatter,
    required this.content,
  });

  final FrontmatterData frontmatter;
  final String content;
}

/// Regex for detecting YAML frontmatter.
final frontmatterRegex = RegExp(r'^---\s*\n([\s\S]*?)---\s*\n?');

/// Characters that require quoting in YAML values.
final _yamlSpecialChars = RegExp(r'[{}\[\]*&#!|>%@`]|: ');

/// Pre-process frontmatter text to quote problematic YAML values.
String _quoteProblematicValues(String frontmatterText) {
  final lines = frontmatterText.split('\n');
  final result = <String>[];

  for (final line in lines) {
    final match = RegExp(r'^([a-zA-Z_-]+):\s+(.+)$').firstMatch(line);
    if (match != null) {
      final key = match.group(1)!;
      final value = match.group(2)!;

      // Skip if already quoted
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        result.add(line);
        continue;
      }

      // Quote if contains special YAML characters
      if (_yamlSpecialChars.hasMatch(value)) {
        final escaped = value
            .replaceAll(r'\', r'\\')
            .replaceAll('"', r'\"');
        result.add('$key: "$escaped"');
        continue;
      }
    }
    result.add(line);
  }

  return result.join('\n');
}

/// Parse markdown content to extract frontmatter and body.
ParsedMarkdown parseFrontmatter(String markdown, {String? sourcePath}) {
  final match = frontmatterRegex.firstMatch(markdown);

  if (match == null) {
    return ParsedMarkdown(frontmatter: {}, content: markdown);
  }

  final frontmatterText = match.group(1) ?? '';
  final content = markdown.substring(match.end);

  FrontmatterData frontmatter = {};
  try {
    final parsed = _parseSimpleYaml(frontmatterText);
    if (parsed is Map<String, dynamic>) {
      frontmatter = parsed;
    }
  } catch (_) {
    // YAML parsing failed - try again after quoting
    try {
      final quotedText = _quoteProblematicValues(frontmatterText);
      final parsed = _parseSimpleYaml(quotedText);
      if (parsed is Map<String, dynamic>) {
        frontmatter = parsed;
      }
    } catch (retryError) {
      final location = sourcePath != null ? ' in $sourcePath' : '';
      stderr.writeln(
        'Failed to parse YAML frontmatter$location: $retryError',
      );
    }
  }

  return ParsedMarkdown(frontmatter: frontmatter, content: content);
}

/// Simple YAML parser for frontmatter (key: value pairs).
/// Does not handle full YAML spec; just enough for frontmatter.
dynamic _parseSimpleYaml(String text) {
  final result = <String, dynamic>{};
  String? currentKey;
  final listBuffer = <String>[];
  var inList = false;

  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) continue;

    // List item
    if (inList && line.startsWith('  - ')) {
      listBuffer.add(line.substring(4).trim());
      continue;
    }

    // End of list
    if (inList && !line.startsWith('  - ') && !line.startsWith('  ')) {
      if (currentKey != null) {
        result[currentKey] = List<String>.from(listBuffer);
        listBuffer.clear();
      }
      inList = false;
    }

    // Key: value
    final kvMatch = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$').firstMatch(line);
    if (kvMatch != null) {
      final key = kvMatch.group(1)!;
      final value = kvMatch.group(2)!.trim();

      currentKey = key;

      if (value.isEmpty) {
        // Could be a list or null
        inList = true;
        listBuffer.clear();
        continue;
      }

      // Remove quotes
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        result[key] = value.substring(1, value.length - 1);
      } else if (value == 'true') {
        result[key] = true;
      } else if (value == 'false') {
        result[key] = false;
      } else if (value == 'null') {
        result[key] = null;
      } else {
        final intVal = int.tryParse(value);
        if (intVal != null) {
          result[key] = intVal;
        } else {
          final doubleVal = double.tryParse(value);
          if (doubleVal != null) {
            result[key] = doubleVal;
          } else {
            result[key] = value;
          }
        }
      }
      inList = false;
    }
  }

  // Flush remaining list
  if (inList && currentKey != null && listBuffer.isNotEmpty) {
    result[currentKey] = List<String>.from(listBuffer);
  }

  return result;
}

/// Split paths in frontmatter, respecting brace patterns.
List<String> splitPathInFrontmatter(dynamic input) {
  if (input is List) {
    return input.expand<String>(
      (item) => splitPathInFrontmatter(item),
    ).toList();
  }
  if (input is! String) return [];

  final parts = <String>[];
  var current = StringBuffer();
  var braceDepth = 0;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (char == '{') {
      braceDepth++;
      current.write(char);
    } else if (char == '}') {
      braceDepth--;
      current.write(char);
    } else if (char == ',' && braceDepth == 0) {
      final trimmed = current.toString().trim();
      if (trimmed.isNotEmpty) parts.add(trimmed);
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }

  final trimmed = current.toString().trim();
  if (trimmed.isNotEmpty) parts.add(trimmed);

  return parts
      .where((p) => p.isNotEmpty)
      .expand((pattern) => expandBraces(pattern))
      .toList();
}

/// Expand brace patterns in a glob string.
List<String> expandBraces(String pattern) {
  final braceMatch = RegExp(r'^([^{]*)\{([^}]+)\}(.*)$').firstMatch(pattern);
  if (braceMatch == null) return [pattern];

  final prefix = braceMatch.group(1) ?? '';
  final alternatives = braceMatch.group(2) ?? '';
  final suffix = braceMatch.group(3) ?? '';

  final parts = alternatives.split(',').map((s) => s.trim());
  final expanded = <String>[];
  for (final part in parts) {
    expanded.addAll(expandBraces('$prefix$part$suffix'));
  }
  return expanded;
}

/// Parse a positive integer from frontmatter.
int? parsePositiveIntFromFrontmatter(dynamic value) {
  if (value == null) return null;
  final parsed = value is int ? value : int.tryParse('$value');
  if (parsed != null && parsed > 0) return parsed;
  return null;
}

/// Coerce a description value from frontmatter to a string.
String? coerceDescriptionToString(
  dynamic value, {
  String? componentName,
  String? pluginName,
}) {
  if (value == null) return null;
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  if (value is num || value is bool) return '$value';
  // Non-scalar
  final source = pluginName != null
      ? '$pluginName:$componentName'
      : (componentName ?? 'unknown');
  stderr.writeln('Description invalid for $source - omitting');
  return null;
}

/// Parse a boolean frontmatter value.
bool parseBooleanFrontmatter(dynamic value) {
  return value == true || value == 'true';
}

/// Accepted shell values for frontmatter.
enum FrontmatterShell { bash, powershell }

/// Parse and validate the `shell:` frontmatter field.
FrontmatterShell? parseShellFrontmatter(dynamic value, {required String source}) {
  if (value == null) return null;
  final normalized = '$value'.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  switch (normalized) {
    case 'bash':
      return FrontmatterShell.bash;
    case 'powershell':
      return FrontmatterShell.powershell;
    default:
      stderr.writeln(
        "Frontmatter 'shell: $value' in $source is not recognized. "
        'Valid values: bash, powershell. Falling back to bash.',
      );
      return null;
  }
}
