/// Output formatting and styling utilities.
///
/// Provides structured formatters for CLI-style output including tool
/// results, errors, diffs, file lists, tables, progress bars, and
/// human-readable byte/token/cost formatting.
library;

import 'dart:convert';
import 'dart:math' as math;

/// Supported output formats.
enum OutputFormat { plain, rich, json, markdown, minimal }

/// Color palette for themed output rendering.
///
/// Each field holds an ANSI escape code string (e.g. `'\x1B[32m'`).
class OutputTheme {
  final String success;
  final String error;
  final String warning;
  final String info;
  final String muted;
  final String highlight;
  final String code;
  final String path;
  final String number;
  final String reset;

  const OutputTheme({
    this.success = '\x1B[32m',
    this.error = '\x1B[31m',
    this.warning = '\x1B[33m',
    this.info = '\x1B[36m',
    this.muted = '\x1B[90m',
    this.highlight = '\x1B[1;37m',
    this.code = '\x1B[35m',
    this.path = '\x1B[34m',
    this.number = '\x1B[33m',
    this.reset = '\x1B[0m',
  });

  /// A theme with no ANSI codes (plain text).
  static const OutputTheme none = OutputTheme(
    success: '',
    error: '',
    warning: '',
    info: '',
    muted: '',
    highlight: '',
    code: '',
    path: '',
    number: '',
    reset: '',
  );
}

/// Column alignment for table formatting.
enum ColumnAlignment { left, right, center }

/// Formats structured output for terminal display.
///
/// Supports multiple [OutputFormat] modes and applies colors from the
/// active [OutputTheme].
class OutputFormatter {
  /// The current output format.
  OutputFormat format;

  /// The active color theme.
  OutputTheme theme;

  OutputFormatter({
    this.format = OutputFormat.rich,
    this.theme = const OutputTheme(),
  });

  /// Formats tool execution output with a header.
  String formatToolOutput(
    String toolName,
    String output, {
    OutputFormat? format,
  }) {
    final fmt = format ?? this.format;
    switch (fmt) {
      case OutputFormat.plain:
        return '[$toolName]\n$output';
      case OutputFormat.rich:
        return '${theme.info}[$toolName]${theme.reset}\n$output';
      case OutputFormat.json:
        return '{"tool":"$toolName","output":${_jsonEscape(output)}}';
      case OutputFormat.markdown:
        return '### $toolName\n\n```\n$output\n```';
      case OutputFormat.minimal:
        return output;
    }
  }

  /// Formats an error message with optional stack trace.
  String formatError(
    Object error, {
    StackTrace? stackTrace,
    bool verbose = false,
  }) {
    final msg = error.toString();
    final buf = StringBuffer();
    buf.write('${theme.error}Error: $msg${theme.reset}');
    if (verbose && stackTrace != null) {
      buf.write('\n${theme.muted}$stackTrace${theme.reset}');
    }
    return buf.toString();
  }

  /// Formats a unified diff string with optional ANSI colors.
  String formatDiff(String diff, {bool colorize = true}) {
    if (!colorize) return diff;
    final lines = diff.split('\n');
    final buf = StringBuffer();
    for (final line in lines) {
      if (line.startsWith('+')) {
        buf.writeln('${theme.success}$line${theme.reset}');
      } else if (line.startsWith('-')) {
        buf.writeln('${theme.error}$line${theme.reset}');
      } else if (line.startsWith('@@')) {
        buf.writeln('${theme.info}$line${theme.reset}');
      } else {
        buf.writeln(line);
      }
    }
    return buf.toString().trimRight();
  }

  /// Formats a list of file paths with optional size and date columns.
  String formatFileList(
    List<String> files, {
    List<int>? sizes,
    List<DateTime>? dates,
    bool showSize = false,
    bool showDate = false,
  }) {
    final buf = StringBuffer();
    for (var i = 0; i < files.length; i++) {
      final parts = <String>[];
      if (showSize && sizes != null && i < sizes.length) {
        parts.add(formatBytes(sizes[i]).padLeft(10));
      }
      if (showDate && dates != null && i < dates.length) {
        parts.add(_formatDate(dates[i]));
      }
      parts.add('${theme.path}${files[i]}${theme.reset}');
      buf.writeln(parts.join('  '));
    }
    return buf.toString().trimRight();
  }

  /// Formats a table with aligned columns and optional borders.
  String formatTable(
    List<String> headers,
    List<List<String>> rows, {
    List<ColumnAlignment>? alignment,
    bool border = true,
  }) {
    final colCount = headers.length;
    final widths = List<int>.filled(colCount, 0);
    for (var c = 0; c < colCount; c++) {
      widths[c] = headers[c].length;
      for (final row in rows) {
        if (c < row.length && row[c].length > widths[c]) {
          widths[c] = row[c].length;
        }
      }
    }

    String pad(String text, int width, ColumnAlignment align) {
      switch (align) {
        case ColumnAlignment.right:
          return text.padLeft(width);
        case ColumnAlignment.center:
          final total = width - text.length;
          final left = total ~/ 2;
          return ' ' * left + text + ' ' * (total - left);
        case ColumnAlignment.left:
          return text.padRight(width);
      }
    }

    final aligns = alignment ?? List.filled(colCount, ColumnAlignment.left);

    final buf = StringBuffer();
    final separator = border
        ? widths.map((w) => '─' * (w + 2)).join(border ? '┼' : '')
        : '';

    // Header row.
    final headerCells = <String>[];
    for (var c = 0; c < colCount; c++) {
      headerCells.add(' ${pad(headers[c], widths[c], aligns[c])} ');
    }
    buf.writeln(headerCells.join(border ? '│' : ' '));
    if (border) buf.writeln(separator);

    // Data rows.
    for (final row in rows) {
      final cells = <String>[];
      for (var c = 0; c < colCount; c++) {
        final val = c < row.length ? row[c] : '';
        cells.add(' ${pad(val, widths[c], aligns[c])} ');
      }
      buf.writeln(cells.join(border ? '│' : ' '));
    }
    return buf.toString().trimRight();
  }

  /// Renders an ASCII progress bar.
  String formatProgress(
    int current,
    int total, {
    String? label,
    int barWidth = 30,
  }) {
    final pct = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
    final filled = (pct * barWidth).round();
    final empty = barWidth - filled;
    final bar = '${'█' * filled}${'░' * empty}';
    final pctStr = '${(pct * 100).toStringAsFixed(0)}%';
    final prefix = label != null ? '$label ' : '';
    return '$prefix${theme.info}$bar${theme.reset} '
        '${theme.number}$pctStr${theme.reset} ($current/$total)';
  }

  /// Formats a [Duration] as a human-readable string (e.g. `2m 13s`).
  String formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      final m = duration.inMinutes.remainder(60);
      return '${duration.inHours}h ${m}m';
    }
    if (duration.inMinutes > 0) {
      final s = duration.inSeconds.remainder(60);
      return '${duration.inMinutes}m ${s}s';
    }
    if (duration.inSeconds > 0) {
      return '${duration.inSeconds}s';
    }
    return '${duration.inMilliseconds}ms';
  }

  /// Formats a byte count in human-readable units (KB, MB, GB).
  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Formats a token count with K/M suffixes.
  String formatTokenCount(int tokens) {
    if (tokens < 1000) return '$tokens';
    if (tokens < 1000000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return '${(tokens / 1000000).toStringAsFixed(1)}M';
  }

  /// Formats a dollar cost value (e.g. `$0.00`, `$1.23`).
  String formatCost(double cost) {
    return '\$${cost.toStringAsFixed(2)}';
  }

  /// Truncates [text] to [maxLength] characters, appending an ellipsis.
  String truncateWithEllipsis(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    if (maxLength <= 3) return text.substring(0, maxLength);
    return '${text.substring(0, maxLength - 3)}...';
  }

  /// Indents every line of [text] by [level] repetitions of [char].
  String indentBlock(String text, {int level = 1, String char = '  '}) {
    final prefix = char * level;
    return text.split('\n').map((l) => '$prefix$l').join('\n');
  }

  /// Wraps [text] in an ASCII box with an optional [title].
  String wrapInBox(String text, {String? title, int? width}) {
    final lines = text.split('\n');
    final contentWidth =
        width ?? lines.fold<int>(0, (m, l) => math.max(m, l.length));
    final boxWidth = math.max(
      contentWidth,
      title != null ? title.length + 2 : 0,
    );

    final buf = StringBuffer();
    // Top border.
    if (title != null) {
      buf.writeln('┌─ $title ${'─' * (boxWidth - title.length - 2)}┐');
    } else {
      buf.writeln('┌${'─' * (boxWidth + 2)}┐');
    }
    // Content lines.
    for (final line in lines) {
      buf.writeln('│ ${line.padRight(boxWidth)} │');
    }
    // Bottom border.
    buf.write('└${'─' * (boxWidth + 2)}┘');
    return buf.toString();
  }

  /// Highlights occurrences of [pattern] within [text] using the
  /// theme's highlight color.
  String highlightMatches(String text, Pattern pattern) {
    return text.replaceAllMapped(pattern, (match) {
      return '${theme.highlight}${match.group(0)}${theme.reset}';
    });
  }

  // -- Private helpers --

  String _jsonEscape(String s) {
    return jsonEncode(s);
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)} '
        '${_pad2(dt.hour)}:${_pad2(dt.minute)}';
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}
