// Search service — port of neom_claw search functionality.
// Provides file search, content search, symbol search, and search history.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Scope within which a search is performed.
enum SearchScope {
  /// Search within a single file.
  file,

  /// Search within a directory (non-recursive).
  directory,

  /// Search the entire project (recursive from root).
  project,

  /// Search across all open workspaces.
  workspace,
}

/// Kind of symbol returned by [SearchService.findSymbol].
enum SymbolKind {
  function,
  method,
  classType,
  variable,
  constant,
  enumType,
  interface,
  property,
  field,
  constructor,
  typeAlias,
  other,
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Options that control a search operation.
class SearchOptions {
  /// Whether the search is case-sensitive.
  final bool caseSensitive;

  /// Whether [pattern] should be interpreted as a regular expression.
  final bool regex;

  /// Whether to match whole words only.
  final bool wholeWord;

  /// Glob patterns for files to include (e.g. `['*.dart']`).
  final List<String> includeGlobs;

  /// Glob patterns for files to exclude (e.g. `['*.g.dart']`).
  final List<String> excludeGlobs;

  /// Maximum number of matches to return. Null means unlimited.
  final int? maxResults;

  /// Number of context lines before and after each match.
  final int contextLines;

  const SearchOptions({
    this.caseSensitive = true,
    this.regex = false,
    this.wholeWord = false,
    this.includeGlobs = const [],
    this.excludeGlobs = const [],
    this.maxResults,
    this.contextLines = 0,
  });
}

/// A single match within a file.
class SearchMatch {
  /// Absolute path of the file containing the match.
  final String filePath;

  /// 1-based line number of the match.
  final int lineNumber;

  /// 0-based column offset of the match within the line.
  final int column;

  /// Length of the matched text.
  final int matchLength;

  /// Full text of the line containing the match.
  final String lineContent;

  /// Context lines before the match.
  final List<String> beforeContext;

  /// Context lines after the match.
  final List<String> afterContext;

  const SearchMatch({
    required this.filePath,
    required this.lineNumber,
    required this.column,
    required this.matchLength,
    required this.lineContent,
    this.beforeContext = const [],
    this.afterContext = const [],
  });

  @override
  String toString() => '$filePath:$lineNumber:$column: $lineContent';
}

/// Aggregated result of a search operation.
class SearchResult {
  /// The individual matches.
  final List<SearchMatch> matches;

  /// Total number of matches (may be higher than [matches.length] if
  /// truncated by [SearchOptions.maxResults]).
  final int totalMatches;

  /// Number of files that were searched.
  final int filesSearched;

  /// How long the search took.
  final Duration duration;

  /// Whether the results were truncated by a max-results limit.
  final bool truncated;

  const SearchResult({
    required this.matches,
    required this.totalMatches,
    required this.filesSearched,
    required this.duration,
    this.truncated = false,
  });
}

/// Result of a search-and-replace operation.
class ReplaceResult {
  /// Number of replacements made.
  final int replacements;

  /// Preview of the changes (file path -> before/after pairs).
  final Map<String, List<ReplacementPreview>> preview;

  const ReplaceResult({required this.replacements, required this.preview});
}

/// Preview of a single replacement within a file.
class ReplacementPreview {
  final int lineNumber;
  final String originalLine;
  final String replacedLine;
  const ReplacementPreview({
    required this.lineNumber,
    required this.originalLine,
    required this.replacedLine,
  });
}

/// A symbol found by [SearchService.findSymbol].
class SymbolMatch {
  /// Name of the symbol.
  final String name;

  /// Kind of symbol (function, class, etc.).
  final SymbolKind kind;

  /// Absolute path of the file containing the symbol.
  final String file;

  /// 1-based line number where the symbol is defined.
  final int line;

  /// Name of the containing symbol (e.g. class name for a method).
  final String? containerName;

  const SymbolMatch({
    required this.name,
    required this.kind,
    required this.file,
    required this.line,
    this.containerName,
  });

  @override
  String toString() {
    final container = containerName != null ? ' (in $containerName)' : '';
    return '$name [${kind.name}] $file:$line$container';
  }
}

/// An indexed file for fast word-level search.
class FileIndex {
  /// Absolute path of the indexed file.
  final String path;

  /// Map from word to list of (lineNumber, column) positions.
  final Map<String, List<(int, int)>> wordPositions;

  /// Timestamp of indexing.
  final DateTime indexedAt;

  const FileIndex({
    required this.path,
    required this.wordPositions,
    required this.indexedAt,
  });

  /// Number of unique words in the index.
  int get wordCount => wordPositions.length;
}

/// A saved search entry for history management.
class SearchHistoryEntry {
  final String pattern;
  final SearchScope scope;
  final SearchOptions options;
  final DateTime timestamp;
  final bool pinned;

  const SearchHistoryEntry({
    required this.pattern,
    required this.scope,
    required this.options,
    required this.timestamp,
    this.pinned = false,
  });
}

// ---------------------------------------------------------------------------
// SearchService
// ---------------------------------------------------------------------------

/// Service for searching files, content, and symbols within a project.
class SearchService {
  /// Root directory of the project (used for project-scope searches).
  final String projectRoot;

  /// Maximum entries kept in search history.
  final int maxHistorySize;

  final List<SearchHistoryEntry> _history = [];
  final Map<String, FileIndex> _indexCache = {};

  SearchService({
    required this.projectRoot,
    this.maxHistorySize = 50,
  });

  // -------------------------------------------------------------------------
  // Content search
  // -------------------------------------------------------------------------

  /// Search for [pattern] within the given [scope].
  Future<SearchResult> search(
    String pattern,
    SearchScope scope,
    SearchOptions options, {
    String? targetPath,
  }) async {
    final sw = Stopwatch()..start();

    // Build the regex for matching.
    final regex = _buildRegex(pattern, options);

    // Determine which files to search.
    final files = await _resolveScope(scope, targetPath, options);
    final matches = <SearchMatch>[];
    var totalMatches = 0;
    final maxResults = options.maxResults;

    for (final filePath in files) {
      if (maxResults != null && totalMatches >= maxResults) break;

      final file = File(filePath);
      if (!await file.exists()) continue;

      String content;
      try {
        content = await file.readAsString();
      } catch (_) {
        continue; // skip binary / unreadable files
      }

      final lines = content.split('\n');

      for (var i = 0; i < lines.length; i++) {
        final lineMatches = regex.allMatches(lines[i]);
        for (final m in lineMatches) {
          totalMatches++;
          if (maxResults != null && totalMatches > maxResults) break;

          final beforeCtx = <String>[];
          final afterCtx = <String>[];
          for (var b = math.max(0, i - options.contextLines); b < i; b++) {
            beforeCtx.add(lines[b]);
          }
          for (var a = i + 1;
              a <= math.min(lines.length - 1, i + options.contextLines);
              a++) {
            afterCtx.add(lines[a]);
          }

          matches.add(SearchMatch(
            filePath: filePath,
            lineNumber: i + 1,
            column: m.start,
            matchLength: m.end - m.start,
            lineContent: lines[i],
            beforeContext: beforeCtx,
            afterContext: afterCtx,
          ));
        }
      }
    }

    sw.stop();
    final truncated = maxResults != null && totalMatches > maxResults;

    _addToHistory(pattern, scope, options);

    return SearchResult(
      matches: matches,
      totalMatches: totalMatches,
      filesSearched: files.length,
      duration: sw.elapsed,
      truncated: truncated,
    );
  }

  /// Search for [pattern] and preview replacements with [replacement].
  ///
  /// Does **not** write changes to disk. Returns a [ReplaceResult] with
  /// a preview of what would change.
  Future<ReplaceResult> searchAndReplace(
    String pattern,
    String replacement,
    SearchScope scope,
    SearchOptions options, {
    String? targetPath,
  }) async {
    final result = await search(pattern, scope, options, targetPath: targetPath);
    final preview = <String, List<ReplacementPreview>>{};
    var count = 0;
    final regex = _buildRegex(pattern, options);

    for (final match in result.matches) {
      final replaced = match.lineContent.replaceAll(regex, replacement);
      if (replaced != match.lineContent) {
        preview.putIfAbsent(match.filePath, () => []).add(
          ReplacementPreview(
            lineNumber: match.lineNumber,
            originalLine: match.lineContent,
            replacedLine: replaced,
          ),
        );
        count++;
      }
    }

    return ReplaceResult(replacements: count, preview: preview);
  }

  // -------------------------------------------------------------------------
  // File search
  // -------------------------------------------------------------------------

  /// Find files matching [globPattern] under [rootDir] (defaults to
  /// [projectRoot]).
  Future<List<String>> findFiles(
    String globPattern, {
    String? rootDir,
    List<String> excludes = const [],
  }) async {
    final root = rootDir ?? projectRoot;
    final dir = Directory(root);
    if (!await dir.exists()) return const [];

    final regex = _globToRegex(globPattern);
    final results = <String>[];

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(root.length + 1);
      if (!regex.hasMatch(relative)) continue;
      if (excludes.any((ex) => _globToRegex(ex).hasMatch(relative))) continue;
      results.add(entity.path);
    }

    return results;
  }

  // -------------------------------------------------------------------------
  // Symbol search
  // -------------------------------------------------------------------------

  /// Find symbol definitions matching [name].
  ///
  /// This performs a regex-based heuristic scan for common declaration
  /// patterns. For precise results, prefer LSP-based symbol search.
  Future<List<SymbolMatch>> findSymbol(
    String name, {
    SymbolKind? kind,
    String? rootDir,
  }) async {
    final root = rootDir ?? projectRoot;
    final dartFiles = await findFiles('*.dart', rootDir: root);
    final results = <SymbolMatch>[];

    // Patterns for common Dart declarations.
    final patterns = <SymbolKind, RegExp>{
      SymbolKind.classType: RegExp(r'^\s*(?:abstract\s+)?class\s+(' + _escRe(name) + r')\b'),
      SymbolKind.function: RegExp(r'^\s*\w[\w<>,\s]*\s+(' + _escRe(name) + r')\s*\('),
      SymbolKind.enumType: RegExp(r'^\s*enum\s+(' + _escRe(name) + r')\b'),
      SymbolKind.variable: RegExp(r'^\s*(?:final|var|const|late)\s+\w+\s+(' + _escRe(name) + r')\b'),
      SymbolKind.typeAlias: RegExp(r'^\s*typedef\s+(' + _escRe(name) + r')\b'),
    };

    // Filter to requested kind if specified.
    final Map<SymbolKind, RegExp?> activePatterns;
    if (kind != null && patterns.containsKey(kind)) {
      activePatterns = {kind: patterns[kind]};
    } else {
      activePatterns = patterns;
    }

    for (final filePath in dartFiles) {
      String content;
      try {
        content = await File(filePath).readAsString();
      } catch (_) {
        continue;
      }

      final lines = content.split('\n');
      String? currentContainer;

      for (var i = 0; i < lines.length; i++) {
        // Track containing class/enum.
        final classMatch = RegExp(r'^\s*(?:abstract\s+)?class\s+(\w+)').firstMatch(lines[i]);
        if (classMatch != null) currentContainer = classMatch.group(1);

        for (final entry in activePatterns.entries) {
          final re = entry.value;
          if (re == null) continue;
          final m = re.firstMatch(lines[i]);
          if (m != null) {
            results.add(SymbolMatch(
              name: m.group(1)!,
              kind: entry.key,
              file: filePath,
              line: i + 1,
              containerName: entry.key != SymbolKind.classType ? currentContainer : null,
            ));
          }
        }
      }
    }
    return results;
  }

  // -------------------------------------------------------------------------
  // Search history
  // -------------------------------------------------------------------------

  /// Get the list of recent searches (most recent first).
  List<SearchHistoryEntry> getHistory() => List.unmodifiable(_history.reversed);

  /// Pin or unpin a history entry.
  void togglePin(int index) {
    if (index < 0 || index >= _history.length) return;
    final entry = _history[index];
    _history[index] = SearchHistoryEntry(
      pattern: entry.pattern,
      scope: entry.scope,
      options: entry.options,
      timestamp: entry.timestamp,
      pinned: !entry.pinned,
    );
  }

  /// Clear unpinned search history.
  void clearHistory() {
    _history.removeWhere((e) => !e.pinned);
  }

  // -------------------------------------------------------------------------
  // File indexing
  // -------------------------------------------------------------------------

  /// Build a word-position index for [path] for fast repeated searches.
  Future<FileIndex> indexFile(String path) async {
    final content = await File(path).readAsString();
    final lines = content.split('\n');
    final positions = <String, List<(int, int)>>{};
    final wordRe = RegExp(r'\w+');

    for (var i = 0; i < lines.length; i++) {
      for (final match in wordRe.allMatches(lines[i])) {
        final word = match.group(0)!.toLowerCase();
        positions.putIfAbsent(word, () => []).add((i + 1, match.start));
      }
    }

    final index = FileIndex(
      path: path,
      wordPositions: positions,
      indexedAt: DateTime.now(),
    );
    _indexCache[path] = index;
    return index;
  }

  /// Retrieve a cached index for [path], or null if not indexed.
  FileIndex? getCachedIndex(String path) => _indexCache[path];

  /// Invalidate the cached index for [path].
  void invalidateIndex(String path) => _indexCache.remove(path);

  // -------------------------------------------------------------------------
  // Ripgrep integration
  // -------------------------------------------------------------------------

  /// Run `rg` (ripgrep) with [pattern] and additional [args], parsing output
  /// into [SearchMatch] objects.
  ///
  /// Falls back to the built-in [search] method if `rg` is not available.
  Future<SearchResult> ripgrepSearch(
    String pattern, {
    List<String> args = const [],
    String? directory,
  }) async {
    final sw = Stopwatch()..start();
    final dir = directory ?? projectRoot;

    try {
      final result = await Process.run('rg', [
        '--json',
        '--line-number',
        ...args,
        pattern,
        dir,
      ]);

      if (result.exitCode != 0 && result.exitCode != 1) {
        // Exit code 1 = no matches; other codes are errors.
        throw ProcessException('rg', args, result.stderr.toString(), result.exitCode);
      }

      final matches = <SearchMatch>[];
      var filesSearched = 0;
      final seenFiles = <String>{};

      for (final line in LineSplitter.split(result.stdout.toString())) {
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'match') {
            final data = json['data'] as Map<String, dynamic>;
            final path = (data['path'] as Map<String, dynamic>)['text'] as String;
            final lineNum = data['line_number'] as int;
            final lineText = (data['lines'] as Map<String, dynamic>)['text'] as String;
            final submatches = data['submatches'] as List<dynamic>;

            seenFiles.add(path);

            for (final sub in submatches) {
              final s = sub as Map<String, dynamic>;
              matches.add(SearchMatch(
                filePath: path,
                lineNumber: lineNum,
                column: s['start'] as int,
                matchLength: (s['end'] as int) - (s['start'] as int),
                lineContent: lineText.trimRight(),
              ));
            }
          } else if (type == 'summary') {
            final data = json['data'] as Map<String, dynamic>;
            final stats = data['stats'] as Map<String, dynamic>?;
            if (stats != null) {
              filesSearched = stats['searches'] as int? ?? seenFiles.length;
            }
          }
        } catch (_) {
          // Skip malformed JSON lines.
        }
      }

      sw.stop();
      return SearchResult(
        matches: matches,
        totalMatches: matches.length,
        filesSearched: filesSearched > 0 ? filesSearched : seenFiles.length,
        duration: sw.elapsed,
      );
    } on ProcessException {
      // rg not found — fall back to built-in search.
      sw.stop();
      return search(
        pattern,
        SearchScope.project,
        const SearchOptions(),
        targetPath: dir,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Build a [RegExp] from a search [pattern] respecting [options].
  RegExp _buildRegex(String pattern, SearchOptions options) {
    var src = options.regex ? pattern : RegExp.escape(pattern);
    if (options.wholeWord) src = '\\b$src\\b';
    return RegExp(src, caseSensitive: options.caseSensitive);
  }

  /// Resolve a [SearchScope] to a list of file paths.
  Future<List<String>> _resolveScope(
    SearchScope scope,
    String? targetPath,
    SearchOptions options,
  ) async {
    final root = targetPath ?? projectRoot;

    switch (scope) {
      case SearchScope.file:
        if (targetPath != null && await File(targetPath).exists()) {
          return [targetPath];
        }
        return const [];
      case SearchScope.directory:
        return _listFilesFlat(root, options);
      case SearchScope.project:
      case SearchScope.workspace:
        return _listFilesRecursive(root, options);
    }
  }

  /// List files in [dir] (non-recursive), applying glob filters.
  Future<List<String>> _listFilesFlat(String dir, SearchOptions options) async {
    final directory = Directory(dir);
    if (!await directory.exists()) return const [];
    final results = <String>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      if (!_matchesGlobs(entity.path, options)) continue;
      results.add(entity.path);
    }
    return results;
  }

  /// List files in [dir] recursively, applying glob filters.
  Future<List<String>> _listFilesRecursive(
    String dir,
    SearchOptions options,
  ) async {
    final directory = Directory(dir);
    if (!await directory.exists()) return const [];
    final results = <String>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      if (!_matchesGlobs(entity.path, options)) continue;
      results.add(entity.path);
    }
    return results;
  }

  /// Check whether [filePath] passes the include/exclude glob filters.
  bool _matchesGlobs(String filePath, SearchOptions options) {
    if (options.includeGlobs.isNotEmpty) {
      final included = options.includeGlobs.any(
        (g) => _globToRegex(g).hasMatch(filePath),
      );
      if (!included) return false;
    }
    if (options.excludeGlobs.isNotEmpty) {
      final excluded = options.excludeGlobs.any(
        (g) => _globToRegex(g).hasMatch(filePath),
      );
      if (excluded) return false;
    }
    return true;
  }

  /// Convert a simple glob pattern to a [RegExp].
  RegExp _globToRegex(String glob) {
    final buf = StringBuffer();
    for (var i = 0; i < glob.length; i++) {
      final c = glob[i];
      switch (c) {
        case '*':
          if (i + 1 < glob.length && glob[i + 1] == '*') {
            buf.write('.*');
            i++; // skip second *
          } else {
            buf.write('[^/]*');
          }
          break;
        case '?':
          buf.write('[^/]');
          break;
        case '.':
          buf.write('\\.');
          break;
        case '{':
          buf.write('(');
          break;
        case '}':
          buf.write(')');
          break;
        case ',':
          buf.write('|');
          break;
        default:
          buf.write(c);
      }
    }
    return RegExp(buf.toString());
  }

  /// Escape a string for use in a regex.
  String _escRe(String s) => RegExp.escape(s);

  /// Add a search to history.
  void _addToHistory(String pattern, SearchScope scope, SearchOptions options) {
    // Remove duplicate.
    _history.removeWhere((e) => e.pattern == pattern && !e.pinned);
    _history.add(SearchHistoryEntry(
      pattern: pattern,
      scope: scope,
      options: options,
      timestamp: DateTime.now(),
    ));
    // Trim to max size (keep pinned).
    while (_history.length > maxHistorySize) {
      final idx = _history.indexWhere((e) => !e.pinned);
      if (idx == -1) break;
      _history.removeAt(idx);
    }
  }
}
