/// Text manipulation utilities.
///
/// Provides string transformations, case conversions, similarity metrics,
/// extraction helpers, and formatting functions.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Span type for highlight diffs
// ---------------------------------------------------------------------------

/// A span of text optionally highlighted.
class Span {
  final String text;
  final bool isHighlighted;

  const Span(this.text, {this.isHighlighted = false});

  @override
  String toString() => isHighlighted ? '[[$text]]' : text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Span &&
          text == other.text &&
          isHighlighted == other.isHighlighted;

  @override
  int get hashCode => Object.hash(text, isHighlighted);
}

// ---------------------------------------------------------------------------
// Truncation & wrapping
// ---------------------------------------------------------------------------

/// Truncate [text] to [maxLen] characters, appending [ellipsis] if truncated.
String truncate(String text, int maxLen, {String ellipsis = '...'}) {
  if (text.length <= maxLen) return text;
  final end = maxLen - ellipsis.length;
  if (end <= 0) return ellipsis.substring(0, maxLen);
  return '${text.substring(0, end)}$ellipsis';
}

/// Word-wrap [text] to the given [width].
///
/// Splits on whitespace boundaries. Lines longer than [width] with no
/// whitespace are broken at exactly [width].
String wordWrap(String text, int width) {
  if (width <= 0) return text;
  final inputLines = text.split('\n');
  final output = <String>[];

  for (final line in inputLines) {
    if (line.length <= width) {
      output.add(line);
      continue;
    }
    final words = line.split(RegExp(r'\s+'));
    final buf = StringBuffer();
    for (final word in words) {
      if (buf.isEmpty) {
        if (word.length > width) {
          // Break long word
          var remaining = word;
          while (remaining.length > width) {
            output.add(remaining.substring(0, width));
            remaining = remaining.substring(width);
          }
          buf.write(remaining);
        } else {
          buf.write(word);
        }
      } else if (buf.length + 1 + word.length <= width) {
        buf.write(' $word');
      } else {
        output.add(buf.toString());
        buf.clear();
        if (word.length > width) {
          var remaining = word;
          while (remaining.length > width) {
            output.add(remaining.substring(0, width));
            remaining = remaining.substring(width);
          }
          buf.write(remaining);
        } else {
          buf.write(word);
        }
      }
    }
    if (buf.isNotEmpty) output.add(buf.toString());
  }

  return output.join('\n');
}

// ---------------------------------------------------------------------------
// Indentation
// ---------------------------------------------------------------------------

/// Indent every line of [text] by [level] repetitions of [char].
String indent(String text, int level, {String char = '  '}) {
  final prefix = char * level;
  return text.split('\n').map((l) => '$prefix$l').join('\n');
}

/// Remove the common leading whitespace from all non-empty lines.
String dedent(String text) {
  final lines = text.split('\n');
  final nonEmpty = lines.where((l) => l.trimLeft().isNotEmpty);
  if (nonEmpty.isEmpty) return text;

  final minIndent = nonEmpty
      .map((l) {
        final stripped = l.trimLeft();
        return l.length - stripped.length;
      })
      .reduce(math.min);

  return lines
      .map((l) {
        if (l.trimLeft().isEmpty) return l.trimRight();
        return l.substring(math.min(minIndent, l.length));
      })
      .join('\n');
}

// ---------------------------------------------------------------------------
// Padding
// ---------------------------------------------------------------------------

/// Pad [text] on the right to [width] with [char].
String padRight(String text, int width, {String char = ' '}) {
  if (text.length >= width) return text;
  final needed = width - text.length;
  final padding = (char * ((needed + char.length - 1) ~/ char.length))
      .substring(0, needed);
  return '$text$padding';
}

/// Pad [text] on the left to [width] with [char].
String padLeft(String text, int width, {String char = ' '}) {
  if (text.length >= width) return text;
  final padding = width - text.length;
  return '${char * padding}$text';
}

/// Center [text] within [width] using [char] for padding.
String center(String text, int width, {String char = ' '}) {
  if (text.length >= width) return text;
  final totalPad = width - text.length;
  final leftPad = totalPad ~/ 2;
  final rightPad = totalPad - leftPad;
  return '${char * leftPad}$text${char * rightPad}';
}

// ---------------------------------------------------------------------------
// Escaping
// ---------------------------------------------------------------------------

/// Escape HTML special characters.
String escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

/// Unescape HTML entities back to characters.
String unescapeHtml(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/');
}

/// Escape special regex characters.
String escapeRegex(String text) {
  return text.replaceAllMapped(
    RegExp(r'[.*+?^${}()|[\]\\]'),
    (m) => '\\${m.group(0)}',
  );
}

/// Escape a string for safe use in shell commands.
String escapeShell(String text) {
  if (text.isEmpty) return "''";
  if (RegExp(r'^[a-zA-Z0-9._/=-]+$').hasMatch(text)) return text;
  return "'${text.replaceAll("'", "'\\''")}'";
}

// ---------------------------------------------------------------------------
// Case conversions
// ---------------------------------------------------------------------------

/// Split a string into word components.
List<String> _splitWords(String text) {
  // Handle camelCase, PascalCase, snake_case, kebab-case, space-separated
  return text
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (m) => '${m.group(1)} ${m.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (m) => '${m.group(1)} ${m.group(2)}',
      )
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

/// Convert to camelCase.
String camelCase(String text) {
  final words = _splitWords(text);
  if (words.isEmpty) return '';
  return words.first.toLowerCase() +
      words
          .skip(1)
          .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
          .join();
}

/// Convert to snake_case.
String snakeCase(String text) {
  return _splitWords(text).map((w) => w.toLowerCase()).join('_');
}

/// Convert to PascalCase.
String pascalCase(String text) {
  return _splitWords(
    text,
  ).map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join();
}

/// Convert to kebab-case.
String kebabCase(String text) {
  return _splitWords(text).map((w) => w.toLowerCase()).join('-');
}

/// Convert to Title Case.
String titleCase(String text) {
  return _splitWords(
    text,
  ).map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
}

// ---------------------------------------------------------------------------
// Pluralization / humanization
// ---------------------------------------------------------------------------

/// Simple English pluralization.
String pluralize(String word, int count) {
  if (count == 1) return word;
  if (word.endsWith('s') ||
      word.endsWith('x') ||
      word.endsWith('z') ||
      word.endsWith('ch') ||
      word.endsWith('sh')) {
    return '${word}es';
  }
  if (word.endsWith('y') &&
      word.length > 1 &&
      !'aeiou'.contains(word[word.length - 2])) {
    return '${word.substring(0, word.length - 1)}ies';
  }
  if (word.endsWith('f')) {
    return '${word.substring(0, word.length - 1)}ves';
  }
  if (word.endsWith('fe')) {
    return '${word.substring(0, word.length - 2)}ves';
  }
  return '${word}s';
}

/// Convert a number to its ordinal string (1st, 2nd, 3rd, etc.).
String ordinalize(int number) {
  final abs = number.abs();
  final lastTwo = abs % 100;
  final lastOne = abs % 10;

  String suffix;
  if (lastTwo >= 11 && lastTwo <= 13) {
    suffix = 'th';
  } else {
    suffix = switch (lastOne) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
  return '$number$suffix';
}

/// Convert a programmatic identifier to human-readable text.
String humanize(String text) {
  final words = _splitWords(text);
  if (words.isEmpty) return '';
  return words.first[0].toUpperCase() +
      words.first.substring(1).toLowerCase() +
      (words.length > 1
          ? ' ${words.skip(1).map((w) => w.toLowerCase()).join(' ')}'
          : '');
}

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

final _urlRegex = RegExp(
  r'https?://[^\s<>\[\](){}"\x27,;]+',
  caseSensitive: false,
);

/// Extract all URLs from [text].
List<String> extractUrls(String text) {
  return _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
}

final _emailRegex = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');

/// Extract all email addresses from [text].
List<String> extractEmails(String text) {
  return _emailRegex.allMatches(text).map((m) => m.group(0)!).toList();
}

/// Extract fenced code blocks from Markdown [text].
///
/// Returns a list of (language, code) pairs.
List<({String language, String code})> extractCodeBlocks(String text) {
  final re = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
  return re.allMatches(text).map((m) {
    return (language: m.group(1) ?? '', code: m.group(2) ?? '');
  }).toList();
}

// ---------------------------------------------------------------------------
// ANSI stripping
// ---------------------------------------------------------------------------

final _ansiRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]|\x1B\].*?\x07|\x1B\(B');

/// Remove ANSI escape codes from [text].
String stripAnsi(String text) {
  return text.replaceAll(_ansiRegex, '');
}

// ---------------------------------------------------------------------------
// Counting
// ---------------------------------------------------------------------------

/// Count non-overlapping occurrences of [pattern] in [text].
int countOccurrences(String text, String pattern) {
  if (pattern.isEmpty) return 0;
  var count = 0;
  var start = 0;
  while (true) {
    final idx = text.indexOf(pattern, start);
    if (idx == -1) break;
    count++;
    start = idx + pattern.length;
  }
  return count;
}

// ---------------------------------------------------------------------------
// Similarity metrics
// ---------------------------------------------------------------------------

/// Compute the Levenshtein edit distance between [a] and [b].
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Use two-row optimization
  var prev = List.generate(b.length + 1, (i) => i);
  var curr = List.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = [
        prev[j] + 1, // deletion
        curr[j - 1] + 1, // insertion
        prev[j - 1] + cost, // substitution
      ].reduce(math.min);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Compute a similarity score between [a] and [b] based on Levenshtein distance.
///
/// Returns a value between 0.0 (completely different) and 1.0 (identical).
double similarity(String a, String b) {
  if (a == b) return 1.0;
  final maxLen = math.max(a.length, b.length);
  if (maxLen == 0) return 1.0;
  return 1.0 - levenshteinDistance(a, b) / maxLen;
}

/// Compute the Jaccard similarity between the word sets of [a] and [b].
///
/// Returns a value between 0.0 and 1.0.
double jaccardSimilarity(String a, String b) {
  final setA = a.toLowerCase().split(RegExp(r'\s+')).toSet();
  final setB = b.toLowerCase().split(RegExp(r'\s+')).toSet();
  if (setA.isEmpty && setB.isEmpty) return 1.0;

  final intersection = setA.intersection(setB).length;
  final union = setA.union(setB).length;
  if (union == 0) return 1.0;
  return intersection / union;
}

// ---------------------------------------------------------------------------
// Highlight differences
// ---------------------------------------------------------------------------

/// Produce a pair of [Span] lists highlighting character-level differences
/// between [oldText] and [newText].
(List<Span>, List<Span>) highlightDifferences(String oldText, String newText) {
  final oldChars = oldText.split('');
  final newChars = newText.split('');

  // LCS for alignment
  final m = oldChars.length;
  final n = newChars.length;
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (oldChars[i - 1] == newChars[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1]);
      }
    }
  }

  // Backtrack to find common characters
  final oldHighlight = List.filled(m, true);
  final newHighlight = List.filled(n, true);
  var i = m, j = n;
  while (i > 0 && j > 0) {
    if (oldChars[i - 1] == newChars[j - 1]) {
      oldHighlight[i - 1] = false;
      newHighlight[j - 1] = false;
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }

  // Build spans by grouping consecutive same-highlight characters
  List<Span> buildSpans(List<String> chars, List<bool> highlights) {
    if (chars.isEmpty) return [];
    final spans = <Span>[];
    var buf = StringBuffer(chars[0]);
    var hl = highlights[0];
    for (var k = 1; k < chars.length; k++) {
      if (highlights[k] == hl) {
        buf.write(chars[k]);
      } else {
        spans.add(Span(buf.toString(), isHighlighted: hl));
        buf = StringBuffer(chars[k]);
        hl = highlights[k];
      }
    }
    spans.add(Span(buf.toString(), isHighlighted: hl));
    return spans;
  }

  return (
    buildSpans(oldChars, oldHighlight),
    buildSpans(newChars, newHighlight),
  );
}

// ---------------------------------------------------------------------------
// Line splitting
// ---------------------------------------------------------------------------

/// Split [text] into lines.
///
/// If [preserveNewlines] is true, trailing newline characters are kept on
/// each line.
List<String> splitLines(String text, {bool preserveNewlines = false}) {
  if (preserveNewlines) {
    final result = <String>[];
    final re = RegExp(r'[^\n]*\n?');
    for (final m in re.allMatches(text)) {
      final s = m.group(0)!;
      if (s.isNotEmpty) result.add(s);
    }
    return result;
  }
  return text.split('\n');
}

// ---------------------------------------------------------------------------
// Whitespace normalization
// ---------------------------------------------------------------------------

/// Collapse runs of whitespace into single spaces and trim.
String normalizeWhitespace(String text) {
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------------
// Comment removal
// ---------------------------------------------------------------------------

/// Remove comments from source [text].
///
/// Supported [language] values:
/// - `'c'`, `'cpp'`, `'java'`, `'dart'`, `'js'`, `'ts'` — `//` and `/* */`
/// - `'python'`, `'ruby'`, `'shell'`, `'bash'` — `#`
/// - `'html'`, `'xml'` — `<!-- -->`
/// - `'sql'` — `--` and `/* */`
///
/// If [language] is null, removes `//`, `/* */`, and `#` style comments.
String removeComments(String text, {String? language}) {
  final lang = language?.toLowerCase();

  String removeLineComments(String src, String marker) {
    return src
        .split('\n')
        .map((line) {
          // Naive: does not handle strings containing the marker
          final idx = line.indexOf(marker);
          if (idx == -1) return line;
          // Check we are not inside a string (simple heuristic)
          final beforeMarker = line.substring(0, idx);
          final singleQuotes = "'".allMatches(beforeMarker).length;
          final doubleQuotes = '"'.allMatches(beforeMarker).length;
          if (singleQuotes % 2 != 0 || doubleQuotes % 2 != 0) return line;
          return line.substring(0, idx);
        })
        .join('\n');
  }

  String removeBlockComments(String src, String open, String close) {
    final buf = StringBuffer();
    var i = 0;
    while (i < src.length) {
      final openIdx = src.indexOf(open, i);
      if (openIdx == -1) {
        buf.write(src.substring(i));
        break;
      }
      buf.write(src.substring(i, openIdx));
      final closeIdx = src.indexOf(close, openIdx + open.length);
      if (closeIdx == -1) {
        // Unterminated block comment - remove to end
        break;
      }
      i = closeIdx + close.length;
    }
    return buf.toString();
  }

  var result = text;

  switch (lang) {
    case 'python' || 'ruby' || 'shell' || 'bash':
      result = removeLineComments(result, '#');
    case 'html' || 'xml':
      result = removeBlockComments(result, '<!--', '-->');
    case 'sql':
      result = removeLineComments(result, '--');
      result = removeBlockComments(result, '/*', '*/');
    case 'c' ||
        'cpp' ||
        'java' ||
        'dart' ||
        'js' ||
        'ts' ||
        'javascript' ||
        'typescript' ||
        'swift' ||
        'kotlin' ||
        'go' ||
        'rust':
      result = removeBlockComments(result, '/*', '*/');
      result = removeLineComments(result, '//');
    default:
      // General: remove all common comment styles
      result = removeBlockComments(result, '/*', '*/');
      result = removeLineComments(result, '//');
      result = removeLineComments(result, '#');
  }

  return result;
}
