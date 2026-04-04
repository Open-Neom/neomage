// GrepTool — faithful port of neom_claw/src/tools/GrepTool/GrepTool.ts
// Search file contents with regex using ripgrep.
//
// Supports three output modes:
//   - files_with_matches (default): list file paths sorted by mtime
//   - content: show matching lines with optional context
//   - count: show per-file match counts with totals
//
// Supports head_limit / offset pagination, glob filtering, type filtering,
// multiline mode, case-insensitive search, and VCS directory exclusion.

import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

import 'tool.dart';

// ── Constants ──────────────────────────────────────────────────────────────

/// Tool name matching the TS original.
const String grepToolName = 'Grep';

/// Version control directories excluded from searches automatically
/// to avoid noise from VCS metadata.
const List<String> vcsDirectoriesToExclude = [
  '.git',
  '.svn',
  '.hg',
  '.bzr',
  '.jj',
  '.sl',
];

/// Default cap on grep results when head_limit is unspecified.
/// Unbounded content-mode greps can fill up to the 20KB persist threshold
/// (~6-24K tokens / grep-heavy session). 250 is generous enough for
/// exploratory searches while preventing context bloat.
/// Pass head_limit=0 explicitly for unlimited.
const int defaultHeadLimit = 250;

/// Maximum result size before disk persistence (20K chars).
const int maxResultSizeChars = 20000;

// ── Head-limit / offset pagination ─────────────────────────────────────

/// Result of applying head_limit and offset to a list.
class HeadLimitResult<T> {
  final List<T> items;

  /// Only set when truncation actually occurred, so the model knows
  /// there may be more results and can paginate with offset.
  final int? appliedLimit;

  const HeadLimitResult({required this.items, this.appliedLimit});
}

/// Apply head_limit and offset to a list of items.
/// Explicit 0 = unlimited escape hatch.
HeadLimitResult<T> applyHeadLimit<T>(
  List<T> items,
  int? limit, {
  int offset = 0,
}) {
  // Explicit 0 = unlimited escape hatch
  if (limit == 0) {
    return HeadLimitResult(
      items: offset > 0 ? items.sublist(offset.clamp(0, items.length)) : items,
    );
  }
  final effectiveLimit = limit ?? defaultHeadLimit;
  final start = offset.clamp(0, items.length);
  final end = (start + effectiveLimit).clamp(0, items.length);
  final sliced = items.sublist(start, end);

  // Only report appliedLimit when truncation actually occurred
  final wasTruncated = (items.length - start) > effectiveLimit;
  return HeadLimitResult(
    items: sliced,
    appliedLimit: wasTruncated ? effectiveLimit : null,
  );
}

/// Format limit/offset information for display in tool results.
/// appliedLimit is only set when truncation actually occurred (see
/// applyHeadLimit), so it may be undefined even when appliedOffset is set
/// -- build parts conditionally to avoid "limit: undefined" appearing in
/// user-visible output.
String formatLimitInfo(int? appliedLimit, int? appliedOffset) {
  final parts = <String>[];
  if (appliedLimit != null) parts.add('limit: $appliedLimit');
  if (appliedOffset != null && appliedOffset > 0) {
    parts.add('offset: $appliedOffset');
  }
  return parts.join(', ');
}

// ── Output data ────────────────────────────────────────────────────────

/// Structured output from GrepTool.
class GrepOutput {
  final String mode;
  final int numFiles;
  final List<String> filenames;
  final String? content;
  final int? numLines;
  final int? numMatches;
  final int? appliedLimit;
  final int? appliedOffset;

  const GrepOutput({
    required this.mode,
    required this.numFiles,
    required this.filenames,
    this.content,
    this.numLines,
    this.numMatches,
    this.appliedLimit,
    this.appliedOffset,
  });

  Map<String, dynamic> toMap() => {
    'mode': mode,
    'numFiles': numFiles,
    'filenames': filenames,
    if (content != null) 'content': content,
    if (numLines != null) 'numLines': numLines,
    if (numMatches != null) 'numMatches': numMatches,
    if (appliedLimit != null) 'appliedLimit': appliedLimit,
    if (appliedOffset != null) 'appliedOffset': appliedOffset,
  };
}

// ── Glob parsing ───────────────────────────────────────────────────────

/// Split glob patterns, preserving brace expressions.
/// E.g. "*.{ts,tsx} *.dart" -> ["*.{ts,tsx}", "*.dart"]
List<String> parseGlobPatterns(String glob) {
  final patterns = <String>[];
  final rawPatterns = glob.split(RegExp(r'\s+'));
  for (final raw in rawPatterns) {
    if (raw.isEmpty) continue;
    // If pattern contains braces, don't split further
    if (raw.contains('{') && raw.contains('}')) {
      patterns.add(raw);
    } else {
      // Split on commas for patterns without braces
      patterns.addAll(raw.split(',').where((s) => s.isNotEmpty));
    }
  }
  return patterns;
}

// ── Ripgrep argument builder ───────────────────────────────────────────

/// Build ripgrep command-line arguments from tool input.
List<String> buildRipgrepArgs({
  required String pattern,
  String? glob,
  String? type,
  String outputMode = 'files_with_matches',
  int? contextBefore,
  int? contextAfter,
  int? contextC,
  int? context,
  bool showLineNumbers = true,
  bool caseInsensitive = false,
  bool multiline = false,
}) {
  final args = <String>['--hidden'];

  // Exclude VCS directories to avoid noise
  for (final dir in vcsDirectoriesToExclude) {
    args.addAll(['--glob', '!$dir']);
  }

  // Limit line length to prevent base64/minified content from cluttering output
  args.addAll(['--max-columns', '500']);

  // Only apply multiline flags when explicitly requested
  if (multiline) {
    args.addAll(['-U', '--multiline-dotall']);
  }

  // Case insensitive
  if (caseInsensitive) {
    args.add('-i');
  }

  // Output mode flags
  if (outputMode == 'files_with_matches') {
    args.add('-l');
  } else if (outputMode == 'count') {
    args.add('-c');
  }

  // Line numbers for content mode
  if (showLineNumbers && outputMode == 'content') {
    args.add('-n');
  }

  // Context flags: -C/context takes precedence over -B/-A
  if (outputMode == 'content') {
    if (context != null) {
      args.addAll(['-C', context.toString()]);
    } else if (contextC != null) {
      args.addAll(['-C', contextC.toString()]);
    } else {
      if (contextBefore != null) {
        args.addAll(['-B', contextBefore.toString()]);
      }
      if (contextAfter != null) {
        args.addAll(['-A', contextAfter.toString()]);
      }
    }
  }

  // If pattern starts with dash, use -e flag to prevent ripgrep from
  // interpreting it as a command-line option
  if (pattern.startsWith('-')) {
    args.addAll(['-e', pattern]);
  } else {
    args.add(pattern);
  }

  // Type filter
  if (type != null && type.isNotEmpty) {
    args.addAll(['--type', type]);
  }

  // Glob patterns
  if (glob != null && glob.isNotEmpty) {
    final globPatterns = parseGlobPatterns(glob);
    for (final gp in globPatterns) {
      args.addAll(['--glob', gp]);
    }
  }

  return args;
}

// ── Path helpers ───────────────────────────────────────────────────────

/// Convert an absolute path to a relative path from CWD to save tokens.
String toRelativePath(String absolutePath) {
  try {
    return p.relative(absolutePath, from: Directory.current.path);
  } catch (_) {
    return absolutePath;
  }
}

/// Expand ~ and resolve relative paths to absolute.
String expandPath(String path) {
  if (path.startsWith('~/') || path == '~') {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return p.join(home, path.substring(path.startsWith('~/') ? 2 : 1));
  }
  if (!p.isAbsolute(path)) {
    return p.join(Directory.current.path, path);
  }
  return path;
}

/// Plural helper: returns "file" or "files" etc.
String plural(int count, String singular) {
  return count == 1 ? singular : '${singular}s';
}

// ── Main GrepTool class ───────────────────────────────────────────────

/// Search file contents with regex -- port of neom_claw GrepTool.
///
/// Supports three output modes:
///   - files_with_matches: list file paths sorted by modification time
///   - content: show matching lines with optional context (-A/-B/-C)
///   - count: show per-file match counts with totals
///
/// Features head_limit/offset pagination, glob/type filtering,
/// VCS directory exclusion, multiline mode, and case-insensitive search.
class GrepTool extends Tool with ReadOnlyToolMixin {
  @override
  String get name => grepToolName;

  @override
  String get description =>
      'A powerful search tool built on ripgrep. Searches for a pattern in '
      'file contents using regular expressions. Supports full regex syntax, '
      'file filtering with glob/type, context lines, and pagination.';

  @override
  String get prompt => description;

  @override
  bool get strict => true;

  @override
  int? get maxResultSizeChars => 100000;

  @override
  String get userFacingName => 'Search';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'pattern': {
        'type': 'string',
        'description':
            'The regular expression pattern to search for in file contents',
      },
      'path': {
        'type': 'string',
        'description':
            'File or directory to search in (rg PATH). Defaults to '
            'current working directory.',
      },
      'glob': {
        'type': 'string',
        'description':
            'Glob pattern to filter files (e.g. "*.js", "*.{ts,tsx}") '
            '- maps to rg --glob',
      },
      'output_mode': {
        'type': 'string',
        'enum': ['content', 'files_with_matches', 'count'],
        'description':
            'Output mode: "content" shows matching lines, '
            '"files_with_matches" shows file paths (default), '
            '"count" shows match counts.',
      },
      '-B': {
        'type': 'number',
        'description':
            'Number of lines to show before each match (rg -B). '
            'Requires output_mode: "content".',
      },
      '-A': {
        'type': 'number',
        'description':
            'Number of lines to show after each match (rg -A). '
            'Requires output_mode: "content".',
      },
      '-C': {'type': 'number', 'description': 'Alias for context.'},
      'context': {
        'type': 'number',
        'description':
            'Number of lines to show before and after each match (rg -C). '
            'Requires output_mode: "content".',
      },
      '-n': {
        'type': 'boolean',
        'description':
            'Show line numbers in output (rg -n). Requires output_mode: '
            '"content". Defaults to true.',
      },
      '-i': {
        'type': 'boolean',
        'description': 'Case insensitive search (rg -i)',
      },
      'type': {
        'type': 'string',
        'description':
            'File type to search (rg --type). Common types: js, py, '
            'rust, go, java, etc.',
      },
      'head_limit': {
        'type': 'number',
        'description':
            'Limit output to first N lines/entries. Defaults to 250. '
            'Pass 0 for unlimited.',
      },
      'offset': {
        'type': 'number',
        'description':
            'Skip first N lines/entries before applying head_limit. '
            'Defaults to 0.',
      },
      'multiline': {
        'type': 'boolean',
        'description':
            'Enable multiline mode where . matches newlines and '
            'patterns can span lines (rg -U --multiline-dotall). '
            'Default: false.',
      },
    },
    'required': ['pattern'],
  };

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final pattern = input['pattern'] as String? ?? '';
    final path = input['path'] as String?;
    if (path != null && path.isNotEmpty) {
      return '$pattern in ${p.basename(path)}';
    }
    return pattern;
  }

  @override
  String getActivityDescription(Map<String, dynamic> input) {
    final summary = getToolUseSummary(input);
    return summary.isNotEmpty ? 'Searching for $summary' : 'Searching';
  }

  @override
  String toAutoClassifierInput(Map<String, dynamic> input) {
    final pattern = input['pattern'] as String? ?? '';
    final path = input['path'] as String?;
    return path != null ? '$pattern in $path' : pattern;
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final pattern = input['pattern'] as String?;
    if (pattern == null || pattern.isEmpty) {
      return const ValidationResult.invalid(
        'Missing required parameter: pattern',
      );
    }

    // If path is provided, validate it exists
    final path = input['path'] as String?;
    if (path != null && path.isNotEmpty) {
      final absolutePath = expandPath(path);

      // SECURITY: Skip filesystem operations for UNC paths to prevent
      // NTLM credential leaks.
      if (absolutePath.startsWith('\\\\') || absolutePath.startsWith('//')) {
        return const ValidationResult.valid();
      }

      final entity = FileSystemEntity.typeSync(absolutePath);
      if (entity == FileSystemEntityType.notFound) {
        return ValidationResult.invalid(
          'Path does not exist: $path. '
          'Current working directory is ${Directory.current.path}.',
        );
      }
    }

    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final pattern = input['pattern'] as String?;
    if (pattern == null || pattern.isEmpty) {
      return ToolResult.error('Missing required parameter: pattern');
    }

    final searchPath = input['path'] as String?;
    final glob = input['glob'] as String?;
    final type = input['type'] as String?;
    final outputMode = input['output_mode'] as String? ?? 'files_with_matches';
    final contextBefore = _toInt(input['-B']);
    final contextAfter = _toInt(input['-A']);
    final contextC = _toInt(input['-C']);
    final context = _toInt(input['context']);
    final showLineNumbers = input['-n'] as bool? ?? true;
    final caseInsensitive = input['-i'] as bool? ?? false;
    final headLimit = _toInt(input['head_limit']);
    final offset = _toInt(input['offset']) ?? 0;
    final multiline = input['multiline'] as bool? ?? false;

    final absolutePath = searchPath != null && searchPath.isNotEmpty
        ? expandPath(searchPath)
        : Directory.current.path;

    try {
      // Build ripgrep arguments
      final args = buildRipgrepArgs(
        pattern: pattern,
        glob: glob,
        type: type,
        outputMode: outputMode,
        contextBefore: contextBefore,
        contextAfter: contextAfter,
        contextC: contextC,
        context: context,
        showLineNumbers: showLineNumbers,
        caseInsensitive: caseInsensitive,
        multiline: multiline,
      );

      // Run ripgrep
      final results = await _runRipgrep(args, absolutePath);

      // Route to appropriate output mode handler
      switch (outputMode) {
        case 'content':
          return _handleContentMode(results, headLimit, offset);
        case 'count':
          return _handleCountMode(results, headLimit, offset);
        default:
          return await _handleFilesWithMatchesMode(results, headLimit, offset);
      }
    } on RipgrepTimeoutException catch (e) {
      return ToolResult.error(
        'Search timed out after ${e.timeoutMs}ms. Try narrowing your '
        'search with a more specific pattern or path.',
      );
    } catch (e) {
      return ToolResult.error('Search error: $e');
    }
  }

  // ── Output mode handlers ─────────────────────────────────────────────

  /// Handle content output mode: show matching lines with context.
  ToolResult _handleContentMode(
    List<String> results,
    int? headLimit,
    int offset,
  ) {
    // Apply head_limit first -- relativize is per-line work, so
    // avoid processing lines that will be discarded.
    final limited = applyHeadLimit(results, headLimit, offset: offset);

    // Convert absolute paths to relative paths to save tokens
    final finalLines = limited.items.map((line) {
      final colonIndex = line.indexOf(':');
      if (colonIndex > 0) {
        final filePath = line.substring(0, colonIndex);
        final rest = line.substring(colonIndex);
        return toRelativePath(filePath) + rest;
      }
      return line;
    }).toList();

    final output = GrepOutput(
      mode: 'content',
      numFiles: 0, // Not applicable for content mode
      filenames: const [],
      content: finalLines.join('\n'),
      numLines: finalLines.length,
      appliedLimit: limited.appliedLimit,
      appliedOffset: offset > 0 ? offset : null,
    );

    final limitInfo = formatLimitInfo(
      output.appliedLimit,
      output.appliedOffset,
    );
    final resultContent = output.content?.isNotEmpty == true
        ? output.content!
        : 'No matches found';
    final finalContent = limitInfo.isNotEmpty
        ? '$resultContent\n\n[Showing results with pagination = $limitInfo]'
        : resultContent;

    return ToolResult.success(finalContent, metadata: output.toMap());
  }

  /// Handle count output mode: show per-file counts with totals.
  ToolResult _handleCountMode(
    List<String> results,
    int? headLimit,
    int offset,
  ) {
    // Apply head_limit first to avoid relativizing entries that will
    // be discarded.
    final limited = applyHeadLimit(results, headLimit, offset: offset);

    // Convert absolute paths to relative paths to save tokens
    final finalCountLines = limited.items.map((line) {
      final colonIndex = line.lastIndexOf(':');
      if (colonIndex > 0) {
        final filePath = line.substring(0, colonIndex);
        final count = line.substring(colonIndex);
        return toRelativePath(filePath) + count;
      }
      return line;
    }).toList();

    // Parse count output to extract total matches and file count
    var totalMatches = 0;
    var fileCount = 0;
    for (final line in finalCountLines) {
      final colonIndex = line.lastIndexOf(':');
      if (colonIndex > 0) {
        final countStr = line.substring(colonIndex + 1);
        final count = int.tryParse(countStr);
        if (count != null) {
          totalMatches += count;
          fileCount += 1;
        }
      }
    }

    final output = GrepOutput(
      mode: 'count',
      numFiles: fileCount,
      filenames: const [],
      content: finalCountLines.join('\n'),
      numMatches: totalMatches,
      appliedLimit: limited.appliedLimit,
      appliedOffset: offset > 0 ? offset : null,
    );

    final limitInfo = formatLimitInfo(
      output.appliedLimit,
      output.appliedOffset,
    );
    final rawContent = output.content?.isNotEmpty == true
        ? output.content!
        : 'No matches found';
    final occurrences = totalMatches == 1 ? 'occurrence' : 'occurrences';
    final files = fileCount == 1 ? 'file' : 'files';
    final summary =
        '\n\nFound $totalMatches total $occurrences '
        'across $fileCount $files.'
        '${limitInfo.isNotEmpty ? ' with pagination = $limitInfo' : ''}';

    return ToolResult.success(rawContent + summary, metadata: output.toMap());
  }

  /// Handle files_with_matches mode: list file paths sorted by mtime.
  Future<ToolResult> _handleFilesWithMatchesMode(
    List<String> results,
    int? headLimit,
    int offset,
  ) async {
    // Sort by modification time (most recent first), with filename as
    // tiebreaker.
    final statsEntries = <_FileWithMtime>[];
    for (final filePath in results) {
      int mtime = 0;
      try {
        final stat = await File(filePath).stat();
        mtime = stat.modified.millisecondsSinceEpoch;
      } catch (_) {
        // File may have been deleted between ripgrep scan and stat
      }
      statsEntries.add(_FileWithMtime(filePath, mtime));
    }

    statsEntries.sort((a, b) {
      final timeComparison = b.mtime.compareTo(a.mtime);
      if (timeComparison == 0) {
        return a.path.compareTo(b.path);
      }
      return timeComparison;
    });

    final sortedPaths = statsEntries.map((e) => e.path).toList();

    // Apply head_limit to sorted file list
    final limited = applyHeadLimit(sortedPaths, headLimit, offset: offset);

    // Convert absolute paths to relative paths to save tokens
    final relativeMatches = limited.items.map(toRelativePath).toList();

    final output = GrepOutput(
      mode: 'files_with_matches',
      filenames: relativeMatches,
      numFiles: relativeMatches.length,
      appliedLimit: limited.appliedLimit,
      appliedOffset: offset > 0 ? offset : null,
    );

    if (output.numFiles == 0) {
      return ToolResult.success('No files found', metadata: output.toMap());
    }

    final limitInfo = formatLimitInfo(
      output.appliedLimit,
      output.appliedOffset,
    );
    final result =
        'Found ${output.numFiles} '
        '${plural(output.numFiles, "file")}'
        '${limitInfo.isNotEmpty ? ' $limitInfo' : ''}\n'
        '${output.filenames.join('\n')}';

    return ToolResult.success(result, metadata: output.toMap());
  }

  // ── Ripgrep execution ────────────────────────────────────────────────

  /// Run ripgrep with the given arguments in the specified directory.
  /// Returns a list of result lines (file paths, content lines, or
  /// count lines depending on the flags).
  Future<List<String>> _runRipgrep(
    List<String> args,
    String workingDirectory,
  ) async {
    // Try to find ripgrep binary
    final rgPath = await _findRipgrep();

    final result = await Process.run(
      rgPath,
      args,
      workingDirectory: workingDirectory,
    );

    // ripgrep exit codes:
    // 0 = matches found
    // 1 = no matches found (not an error)
    // 2 = error
    if (result.exitCode == 2) {
      final stderr = result.stderr as String;
      if (stderr.isNotEmpty) {
        throw Exception('ripgrep error: $stderr');
      }
    }

    final stdout = result.stdout as String;
    if (stdout.isEmpty) return const [];

    return stdout.split('\n').where((line) => line.isNotEmpty).toList();
  }

  /// Find ripgrep binary path, preferring 'rg' on PATH.
  Future<String> _findRipgrep() async {
    // Try 'rg' directly (most common)
    try {
      final result = await Process.run('which', ['rg']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}

    // Try common installation paths
    final candidates = [
      '/usr/local/bin/rg',
      '/usr/bin/rg',
      '/opt/homebrew/bin/rg',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }

    // Fall back to 'rg' and hope it's on PATH
    return 'rg';
  }

  /// Parse an input value to int, handling both int and double.
  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

// ── Internal helpers ───────────────────────────────────────────────────

class _FileWithMtime {
  final String path;
  final int mtime;
  const _FileWithMtime(this.path, this.mtime);
}

/// Exception thrown when ripgrep times out.
class RipgrepTimeoutException implements Exception {
  final int timeoutMs;
  const RipgrepTimeoutException(this.timeoutMs);
  @override
  String toString() =>
      'RipgrepTimeoutException: timed out after ${timeoutMs}ms';
}
