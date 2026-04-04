// Markdown utilities — port of neom_claw/src/utils/markdown/.
// Markdown parsing, rendering helpers, code block extraction, table formatting.

import 'dart:math';

// ─── Markdown parsing ───

/// Parsed markdown element types.
enum MdElementType {
  paragraph,
  heading1,
  heading2,
  heading3,
  heading4,
  heading5,
  heading6,
  codeBlock,
  codeSpan,
  blockquote,
  unorderedList,
  orderedList,
  listItem,
  horizontalRule,
  link,
  image,
  bold,
  italic,
  strikethrough,
  table,
  tableRow,
  tableCell,
  lineBreak,
  html,
  taskListItem,
  footnote,
  definition,
}

/// A parsed markdown element.
class MdElement {
  final MdElementType type;
  final String content;
  final Map<String, String> attributes;
  final List<MdElement> children;
  final int level; // For headings (1-6), list nesting depth

  const MdElement({
    required this.type,
    this.content = '',
    this.attributes = const {},
    this.children = const [],
    this.level = 0,
  });
}

/// Extract all code blocks from markdown text.
List<({String language, String code, int startLine, int endLine})>
extractCodeBlocks(String markdown) {
  final blocks =
      <({String language, String code, int startLine, int endLine})>[];
  final lines = markdown.split('\n');
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    final fenceMatch = RegExp(r'^(`{3,}|~{3,})\s*(\w*)').firstMatch(line);

    if (fenceMatch != null) {
      final fence = fenceMatch.group(1)!;
      final language = fenceMatch.group(2) ?? '';
      final fenceChar = fence[0];
      final fenceLen = fence.length;
      final startLine = i + 1;
      final codeLines = <String>[];
      i++;

      while (i < lines.length) {
        final closeFence = RegExp(
          '^$fenceChar{$fenceLen,}\\s*\$',
        ).firstMatch(lines[i]);
        if (closeFence != null) {
          break;
        }
        codeLines.add(lines[i]);
        i++;
      }

      blocks.add((
        language: language,
        code: codeLines.join('\n'),
        startLine: startLine,
        endLine: i,
      ));
    }
    i++;
  }

  return blocks;
}

/// Extract all links from markdown text.
List<({String text, String url, String? title})> extractLinks(String markdown) {
  final links = <({String text, String url, String? title})>[];
  final pattern = RegExp(r'\[([^\]]+)\]\(([^)]+?)(?:\s+"([^"]+)")?\)');

  for (final match in pattern.allMatches(markdown)) {
    links.add((
      text: match.group(1)!,
      url: match.group(2)!,
      title: match.group(3),
    ));
  }

  return links;
}

/// Extract all headings from markdown text.
List<({int level, String text, int lineNumber})> extractHeadings(
  String markdown,
) {
  final headings = <({int level, String text, int lineNumber})>[];
  final lines = markdown.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(lines[i]);
    if (match != null) {
      headings.add((
        level: match.group(1)!.length,
        text: match.group(2)!.trim(),
        lineNumber: i + 1,
      ));
    }
  }

  return headings;
}

/// Build a table of contents from headings.
String buildTableOfContents(String markdown, {int maxDepth = 3}) {
  final headings = extractHeadings(markdown);
  final buffer = StringBuffer();

  for (final h in headings) {
    if (h.level > maxDepth) continue;
    final indent = '  ' * (h.level - 1);
    final anchor = h.text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    buffer.writeln('$indent- [${h.text}](#$anchor)');
  }

  return buffer.toString();
}

// ─── Table formatting ───

/// Format data as a markdown table.
String formatTable({
  required List<String> headers,
  required List<List<String>> rows,
  List<TableAlignment>? alignments,
}) {
  // Calculate column widths
  final colCount = headers.length;
  final widths = List<int>.filled(colCount, 0);

  for (var i = 0; i < colCount; i++) {
    widths[i] = headers[i].length;
    for (final row in rows) {
      if (i < row.length) {
        widths[i] = max(widths[i], row[i].length);
      }
    }
    widths[i] = max(widths[i], 3); // Minimum 3 for separator
  }

  final buffer = StringBuffer();

  // Header row
  buffer.write('| ');
  for (var i = 0; i < colCount; i++) {
    buffer.write(headers[i].padRight(widths[i]));
    if (i < colCount - 1) buffer.write(' | ');
  }
  buffer.writeln(' |');

  // Separator row
  buffer.write('| ');
  for (var i = 0; i < colCount; i++) {
    final align = alignments != null && i < alignments.length
        ? alignments[i]
        : TableAlignment.left;
    switch (align) {
      case TableAlignment.left:
        buffer.write(':${'-' * (widths[i] - 1)}');
        break;
      case TableAlignment.center:
        buffer.write(':${'-' * (widths[i] - 2)}:');
        break;
      case TableAlignment.right:
        buffer.write('${'-' * (widths[i] - 1)}:');
        break;
    }
    if (i < colCount - 1) buffer.write(' | ');
  }
  buffer.writeln(' |');

  // Data rows
  for (final row in rows) {
    buffer.write('| ');
    for (var i = 0; i < colCount; i++) {
      final cell = i < row.length ? row[i] : '';
      buffer.write(cell.padRight(widths[i]));
      if (i < colCount - 1) buffer.write(' | ');
    }
    buffer.writeln(' |');
  }

  return buffer.toString();
}

enum TableAlignment { left, center, right }

/// Parse a markdown table into headers and rows.
({List<String> headers, List<List<String>> rows})? parseTable(
  String tableText,
) {
  final lines = tableText.trim().split('\n');
  if (lines.length < 2) return null;

  List<String> parseRow(String line) {
    return line
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
  }

  final headers = parseRow(lines[0]);
  if (headers.isEmpty) return null;

  // Skip separator line (line 1)
  final rows = <List<String>>[];
  for (var i = 2; i < lines.length; i++) {
    final row = parseRow(lines[i]);
    if (row.isNotEmpty) rows.add(row);
  }

  return (headers: headers, rows: rows);
}

// ─── Text formatting ───

/// Wrap text to a maximum line width.
String wordWrap(String text, {int maxWidth = 80}) {
  if (text.length <= maxWidth) return text;

  final buffer = StringBuffer();
  final words = text.split(RegExp(r'\s+'));
  var lineLength = 0;

  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (lineLength + word.length + (lineLength > 0 ? 1 : 0) > maxWidth) {
      buffer.writeln();
      lineLength = 0;
    }
    if (lineLength > 0) {
      buffer.write(' ');
      lineLength++;
    }
    buffer.write(word);
    lineLength += word.length;
  }

  return buffer.toString();
}

/// Strip all markdown formatting, returning plain text.
String stripMarkdown(String markdown) {
  var result = markdown;

  // Remove code blocks
  result = result.replaceAll(RegExp(r'```[\s\S]*?```'), '');
  result = result.replaceAll(RegExp(r'`[^`]+`'), '');

  // Remove headings markers
  result = result.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

  // Remove bold/italic
  result = result.replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1');
  result = result.replaceAll(RegExp(r'__(.+?)__'), r'$1');
  result = result.replaceAll(RegExp(r'\*(.+?)\*'), r'$1');
  result = result.replaceAll(RegExp(r'_(.+?)_'), r'$1');
  result = result.replaceAll(RegExp(r'~~(.+?)~~'), r'$1');

  // Remove links, keep text
  result = result.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');

  // Remove images
  result = result.replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]+\)'), r'$1');

  // Remove blockquote markers
  result = result.replaceAll(RegExp(r'^>\s+', multiLine: true), '');

  // Remove list markers
  result = result.replaceAll(RegExp(r'^[\s]*[-*+]\s+', multiLine: true), '');
  result = result.replaceAll(RegExp(r'^[\s]*\d+\.\s+', multiLine: true), '');

  // Remove horizontal rules
  result = result.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');

  // Remove HTML tags
  result = result.replaceAll(RegExp(r'<[^>]+>'), '');

  // Collapse multiple newlines
  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return result.trim();
}

/// Convert plain text to markdown-safe text (escape special chars).
String escapeMarkdown(String text) {
  const specialChars = [
    '\\',
    '`',
    '*',
    '_',
    '{',
    '}',
    '[',
    ']',
    '(',
    ')',
    '#',
    '+',
    '-',
    '.',
    '!',
    '|',
  ];
  var result = text;
  for (final char in specialChars) {
    result = result.replaceAll(char, '\\$char');
  }
  return result;
}

/// Format a diff as a markdown code block.
String formatDiffAsMarkdown(String diff, {String? title}) {
  final buffer = StringBuffer();
  if (title != null) {
    buffer.writeln('### $title');
    buffer.writeln();
  }
  buffer.writeln('```diff');
  buffer.writeln(diff);
  buffer.writeln('```');
  return buffer.toString();
}

/// Format a file's content as a markdown code block.
String formatFileAsMarkdown(String content, {String? path, String? language}) {
  final lang = language ?? (path != null ? _detectLanguage(path) : null) ?? '';
  return '```$lang\n$content\n```';
}

/// Detect language from file path for code block annotation.
String? _detectLanguage(String path) {
  final ext = path.split('.').last.toLowerCase();
  const langMap = {
    'dart': 'dart',
    'ts': 'typescript',
    'tsx': 'tsx',
    'js': 'javascript',
    'jsx': 'jsx',
    'py': 'python',
    'rb': 'ruby',
    'go': 'go',
    'rs': 'rust',
    'java': 'java',
    'kt': 'kotlin',
    'swift': 'swift',
    'c': 'c',
    'cpp': 'cpp',
    'h': 'c',
    'cs': 'csharp',
    'html': 'html',
    'css': 'css',
    'scss': 'scss',
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'xml': 'xml',
    'md': 'markdown',
    'sql': 'sql',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'zsh',
    'fish': 'fish',
    'ps1': 'powershell',
    'toml': 'toml',
    'ini': 'ini',
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'r': 'r',
    'lua': 'lua',
    'php': 'php',
    'pl': 'perl',
    'scala': 'scala',
    'groovy': 'groovy',
    'ex': 'elixir',
    'exs': 'elixir',
    'erl': 'erlang',
    'hs': 'haskell',
    'clj': 'clojure',
    'ml': 'ocaml',
    'v': 'v',
    'zig': 'zig',
    'nim': 'nim',
  };
  return langMap[ext];
}

/// Format a list of items as a markdown checklist.
String formatChecklist(List<({String text, bool checked})> items) {
  return items
      .map((item) => '- [${item.checked ? 'x' : ' '}] ${item.text}')
      .join('\n');
}

/// Format key-value pairs as a markdown definition list.
String formatDefinitionList(Map<String, String> definitions) {
  return definitions.entries
      .map((e) => '**${e.key}**: ${e.value}')
      .join('\n\n');
}

/// Format a collapsible section (details/summary).
String formatCollapsible(String summary, String content) {
  return '<details>\n<summary>$summary</summary>\n\n$content\n\n</details>';
}

/// Format an admonition/callout.
String formatAdmonition(String type, String content) {
  // GitHub-style
  return '> [!${type.toUpperCase()}]\n> ${content.replaceAll('\n', '\n> ')}';
}

/// Estimate the reading time for markdown content.
Duration estimateReadingTime(String markdown, {int wordsPerMinute = 200}) {
  final plainText = stripMarkdown(markdown);
  final wordCount = plainText.split(RegExp(r'\s+')).length;
  final minutes = wordCount / wordsPerMinute;
  return Duration(seconds: (minutes * 60).round());
}

/// Count words in markdown content.
int countWords(String markdown) {
  final plainText = stripMarkdown(markdown);
  return plainText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}
