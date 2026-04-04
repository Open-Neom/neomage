// Diff visualization widget — port of neom_claw StructuredDiff + utils/diff.
// Renders unified diffs with line numbers, color-coded additions/removals.

import 'package:flutter/material.dart';

/// A parsed diff hunk.
class DiffHunk {
  final int oldStart;
  final int oldLines;
  final int newStart;
  final int newLines;
  final List<DiffLine> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.lines,
  });
}

/// A single diff line.
class DiffLine {
  final DiffLineType type;
  final String content;
  final int? oldLineNumber;
  final int? newLineNumber;

  const DiffLine({
    required this.type,
    required this.content,
    this.oldLineNumber,
    this.newLineNumber,
  });
}

enum DiffLineType { addition, removal, context, header }

/// Parse a unified diff string into hunks.
List<DiffHunk> parseUnifiedDiff(String diffText) {
  final hunks = <DiffHunk>[];
  final lines = diffText.split('\n');

  int i = 0;

  // Skip file headers (--- / +++)
  while (i < lines.length &&
      !lines[i].startsWith('@@') &&
      !lines[i].startsWith('diff ')) {
    i++;
  }

  while (i < lines.length) {
    final line = lines[i];

    if (line.startsWith('@@')) {
      final hunkMatch = RegExp(
        r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
      ).firstMatch(line);

      if (hunkMatch == null) {
        i++;
        continue;
      }

      final oldStart = int.parse(hunkMatch.group(1)!);
      final oldLines = int.tryParse(hunkMatch.group(2) ?? '1') ?? 1;
      final newStart = int.parse(hunkMatch.group(3)!);
      final newLines = int.tryParse(hunkMatch.group(4) ?? '1') ?? 1;

      final hunkLines = <DiffLine>[];
      var oldLine = oldStart;
      var newLine = newStart;

      i++;
      while (i < lines.length && !lines[i].startsWith('@@')) {
        final l = lines[i];
        if (l.startsWith('+')) {
          hunkLines.add(DiffLine(
            type: DiffLineType.addition,
            content: l.substring(1),
            newLineNumber: newLine++,
          ));
        } else if (l.startsWith('-')) {
          hunkLines.add(DiffLine(
            type: DiffLineType.removal,
            content: l.substring(1),
            oldLineNumber: oldLine++,
          ));
        } else if (l.startsWith(' ') || l.isEmpty) {
          hunkLines.add(DiffLine(
            type: DiffLineType.context,
            content: l.isEmpty ? '' : l.substring(1),
            oldLineNumber: oldLine++,
            newLineNumber: newLine++,
          ));
        } else if (l.startsWith('\\')) {
          // "\ No newline at end of file" — skip
        } else {
          break; // Next diff section
        }
        i++;
      }

      hunks.add(DiffHunk(
        oldStart: oldStart,
        oldLines: oldLines,
        newStart: newStart,
        newLines: newLines,
        lines: hunkLines,
      ));
    } else {
      i++;
    }
  }

  return hunks;
}

/// Generate a simple unified diff from old and new content.
String generateDiff({
  required String oldContent,
  required String newContent,
  String oldPath = 'a/file',
  String newPath = 'b/file',
  int contextLines = 3,
}) {
  final oldLines = oldContent.split('\n');
  final newLines = newContent.split('\n');

  // Simple LCS-based diff
  final lcs = _longestCommonSubsequence(oldLines, newLines);
  final hunks = _buildHunks(oldLines, newLines, lcs, contextLines);

  if (hunks.isEmpty) return '';

  final buf = StringBuffer()
    ..writeln('--- $oldPath')
    ..writeln('+++ $newPath');

  for (final hunk in hunks) {
    buf.writeln(
      '@@ -${hunk.oldStart},${hunk.oldLines} '
      '+${hunk.newStart},${hunk.newLines} @@',
    );
    for (final line in hunk.lines) {
      switch (line.type) {
        case DiffLineType.addition:
          buf.writeln('+${line.content}');
        case DiffLineType.removal:
          buf.writeln('-${line.content}');
        case DiffLineType.context:
          buf.writeln(' ${line.content}');
        case DiffLineType.header:
          buf.writeln(line.content);
      }
    }
  }

  return buf.toString();
}

/// Count additions and removals in a diff.
({int additions, int removals}) countLinesChanged(List<DiffHunk> hunks) {
  var additions = 0;
  var removals = 0;
  for (final hunk in hunks) {
    for (final line in hunk.lines) {
      if (line.type == DiffLineType.addition) additions++;
      if (line.type == DiffLineType.removal) removals++;
    }
  }
  return (additions: additions, removals: removals);
}

/// Adjust hunk line numbers by an offset (for partial file diffs).
DiffHunk adjustHunkLineNumbers(DiffHunk hunk, int offset) {
  return DiffHunk(
    oldStart: hunk.oldStart + offset,
    oldLines: hunk.oldLines,
    newStart: hunk.newStart + offset,
    newLines: hunk.newLines,
    lines: hunk.lines.map((l) {
      return DiffLine(
        type: l.type,
        content: l.content,
        oldLineNumber:
            l.oldLineNumber != null ? l.oldLineNumber! + offset : null,
        newLineNumber:
            l.newLineNumber != null ? l.newLineNumber! + offset : null,
      );
    }).toList(),
  );
}

// ── LCS diff algorithm ──

List<List<int>> _longestCommonSubsequence(
  List<String> a,
  List<String> b,
) {
  final m = a.length;
  final n = b.length;
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (a[i - 1] == b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = dp[i - 1][j] > dp[i][j - 1]
            ? dp[i - 1][j]
            : dp[i][j - 1];
      }
    }
  }

  return dp;
}

List<DiffHunk> _buildHunks(
  List<String> oldLines,
  List<String> newLines,
  List<List<int>> dp,
  int contextLines,
) {
  // Build edit script from LCS
  final edits = <({String type, String content, int oldIdx, int newIdx})>[];
  var i = oldLines.length;
  var j = newLines.length;

  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1]) {
      edits.insert(0, (
        type: ' ',
        content: oldLines[i - 1],
        oldIdx: i - 1,
        newIdx: j - 1,
      ));
      i--;
      j--;
    } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
      edits.insert(0, (
        type: '+',
        content: newLines[j - 1],
        oldIdx: -1,
        newIdx: j - 1,
      ));
      j--;
    } else {
      edits.insert(0, (
        type: '-',
        content: oldLines[i - 1],
        oldIdx: i - 1,
        newIdx: -1,
      ));
      i--;
    }
  }

  // Group into hunks with context
  final hunks = <DiffHunk>[];
  final changes = <int>[];
  for (var k = 0; k < edits.length; k++) {
    if (edits[k].type != ' ') changes.add(k);
  }

  if (changes.isEmpty) return [];

  var start = 0;
  while (start < changes.length) {
    var end = start;
    while (end + 1 < changes.length &&
        changes[end + 1] - changes[end] <= contextLines * 2 + 1) {
      end++;
    }

    final from = (changes[start] - contextLines).clamp(0, edits.length);
    final to = (changes[end] + contextLines + 1).clamp(0, edits.length);

    final hunkLines = <DiffLine>[];
    var oldStart = 1;
    var newStart = 1;
    var oldCount = 0;
    var newCount = 0;
    var startSet = false;

    for (var k = from; k < to; k++) {
      final edit = edits[k];
      if (!startSet) {
        oldStart = edit.oldIdx >= 0 ? edit.oldIdx + 1 : oldStart;
        newStart = edit.newIdx >= 0 ? edit.newIdx + 1 : newStart;
        startSet = true;
      }

      switch (edit.type) {
        case '+':
          hunkLines.add(DiffLine(
            type: DiffLineType.addition,
            content: edit.content,
            newLineNumber: edit.newIdx + 1,
          ));
          newCount++;
        case '-':
          hunkLines.add(DiffLine(
            type: DiffLineType.removal,
            content: edit.content,
            oldLineNumber: edit.oldIdx + 1,
          ));
          oldCount++;
        default:
          hunkLines.add(DiffLine(
            type: DiffLineType.context,
            content: edit.content,
            oldLineNumber: edit.oldIdx + 1,
            newLineNumber: edit.newIdx + 1,
          ));
          oldCount++;
          newCount++;
      }
    }

    hunks.add(DiffHunk(
      oldStart: oldStart,
      oldLines: oldCount,
      newStart: newStart,
      newLines: newCount,
      lines: hunkLines,
    ));

    start = end + 1;
  }

  return hunks;
}

// ── Flutter Widgets ──

/// Colors for diff rendering.
class DiffColors {
  final Color addedBackground;
  final Color addedText;
  final Color removedBackground;
  final Color removedText;
  final Color contextText;
  final Color gutterText;
  final Color gutterBackground;
  final Color headerBackground;
  final Color headerText;

  const DiffColors({
    this.addedBackground = const Color(0xFF1A3A1A),
    this.addedText = const Color(0xFF4EC94E),
    this.removedBackground = const Color(0xFF3A1A1A),
    this.removedText = const Color(0xFFE06060),
    this.contextText = const Color(0xFFBBBBBB),
    this.gutterText = const Color(0xFF666666),
    this.gutterBackground = const Color(0xFF1E1E2E),
    this.headerBackground = const Color(0xFF2A2A3A),
    this.headerText = const Color(0xFF8888CC),
  });

  factory DiffColors.light() => const DiffColors(
        addedBackground: Color(0xFFE6FFE6),
        addedText: Color(0xFF1A7A1A),
        removedBackground: Color(0xFFFFE6E6),
        removedText: Color(0xFF9A1A1A),
        contextText: Color(0xFF333333),
        gutterText: Color(0xFF999999),
        gutterBackground: Color(0xFFF5F5F5),
        headerBackground: Color(0xFFE8E8F0),
        headerText: Color(0xFF5555AA),
      );
}

/// Widget that displays a unified diff.
class DiffView extends StatelessWidget {
  final List<DiffHunk> hunks;
  final String? filePath;
  final DiffColors? colors;
  final bool showLineNumbers;
  final TextStyle? textStyle;

  const DiffView({
    super.key,
    required this.hunks,
    this.filePath,
    this.colors,
    this.showLineNumbers = true,
    this.textStyle,
  });

  /// Create from raw diff text.
  factory DiffView.fromText(
    String diffText, {
    Key? key,
    DiffColors? colors,
    bool showLineNumbers = true,
  }) {
    return DiffView(
      key: key,
      hunks: parseUnifiedDiff(diffText),
      colors: colors,
      showLineNumbers: showLineNumbers,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = colors ??
        (Theme.of(context).brightness == Brightness.dark
            ? const DiffColors()
            : DiffColors.light());

    final style = textStyle ??
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
          color: theme.contextText,
        );

    final gutterWidth = _calculateGutterWidth();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (filePath != null) _buildFileHeader(theme, style),
        for (var i = 0; i < hunks.length; i++) ...[
          if (i > 0) _buildHunkSeparator(theme),
          _buildHunkHeader(hunks[i], theme, style),
          ...hunks[i].lines.map(
            (line) => _buildDiffLine(line, theme, style, gutterWidth),
          ),
        ],
      ],
    );
  }

  Widget _buildFileHeader(DiffColors theme, TextStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.headerBackground,
      child: Text(
        filePath!,
        style: style.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.headerText,
        ),
      ),
    );
  }

  Widget _buildHunkHeader(DiffHunk hunk, DiffColors theme, TextStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: theme.headerBackground.withAlpha(128),
      child: Text(
        '@@ -${hunk.oldStart},${hunk.oldLines} '
        '+${hunk.newStart},${hunk.newLines} @@',
        style: style.copyWith(color: theme.headerText, fontSize: 12),
      ),
    );
  }

  Widget _buildHunkSeparator(DiffColors theme) {
    return Container(
      height: 1,
      color: theme.gutterText.withAlpha(51),
    );
  }

  Widget _buildDiffLine(
    DiffLine line,
    DiffColors theme,
    TextStyle style,
    int gutterWidth,
  ) {
    final (bgColor, textColor, prefix) = switch (line.type) {
      DiffLineType.addition => (theme.addedBackground, theme.addedText, '+'),
      DiffLineType.removal =>
        (theme.removedBackground, theme.removedText, '-'),
      DiffLineType.context => (null, theme.contextText, ' '),
      DiffLineType.header => (theme.headerBackground, theme.headerText, ''),
    };

    return Container(
      color: bgColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLineNumbers) ...[
            // Old line number gutter
            Container(
              width: gutterWidth * 8.0 + 8,
              padding: const EdgeInsets.only(right: 4),
              color: theme.gutterBackground,
              alignment: Alignment.centerRight,
              child: Text(
                line.oldLineNumber?.toString() ?? '',
                style: style.copyWith(color: theme.gutterText, fontSize: 12),
              ),
            ),
            // New line number gutter
            Container(
              width: gutterWidth * 8.0 + 8,
              padding: const EdgeInsets.only(right: 4),
              color: theme.gutterBackground,
              alignment: Alignment.centerRight,
              child: Text(
                line.newLineNumber?.toString() ?? '',
                style: style.copyWith(color: theme.gutterText, fontSize: 12),
              ),
            ),
          ],
          // Prefix (+/-)
          SizedBox(
            width: 16,
            child: Text(prefix, style: style.copyWith(color: textColor)),
          ),
          // Content
          Expanded(
            child: Text(
              line.content,
              style: style.copyWith(color: textColor),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  int _calculateGutterWidth() {
    var maxLine = 0;
    for (final hunk in hunks) {
      for (final line in hunk.lines) {
        if (line.oldLineNumber != null && line.oldLineNumber! > maxLine) {
          maxLine = line.oldLineNumber!;
        }
        if (line.newLineNumber != null && line.newLineNumber! > maxLine) {
          maxLine = line.newLineNumber!;
        }
      }
    }
    return maxLine.toString().length;
  }
}

/// Scrollable diff view for large diffs.
class ScrollableDiffView extends StatelessWidget {
  final List<DiffHunk> hunks;
  final String? filePath;
  final DiffColors? colors;
  final double maxHeight;

  const ScrollableDiffView({
    super.key,
    required this.hunks,
    this.filePath,
    this.colors,
    this.maxHeight = 400,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DiffView(
            hunks: hunks,
            filePath: filePath,
            colors: colors,
          ),
        ),
      ),
    );
  }
}
