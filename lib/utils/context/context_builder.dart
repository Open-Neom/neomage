// Context builder — port of neomage/src/utils/context/.
// Builds context for LLM: file contents, git state, project info, search results.

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;

// ─── Types ───

/// A piece of context to include in the prompt.
sealed class ContextItem {
  String get label;
  String get content;
  int get estimatedTokens;
  ContextPriority get priority;
}

/// File content context.
class FileContext extends ContextItem {
  final String path;
  final String fileContent;
  final int startLine;
  final int endLine;
  final String? language;

  FileContext({
    required this.path,
    required this.fileContent,
    this.startLine = 1,
    this.endLine = -1,
    this.language,
  });

  @override
  String get label => p.basename(path);

  @override
  String get content {
    final lines = fileContent.split('\n');
    final end = endLine > 0 ? endLine : lines.length;
    final numbered = <String>[];
    for (var i = startLine - 1; i < end && i < lines.length; i++) {
      numbered.add('${i + 1}\t${lines[i]}');
    }
    return '<file path="$path"${language != null ? ' language="$language"' : ''}>\n'
        '${numbered.join('\n')}\n'
        '</file>';
  }

  @override
  int get estimatedTokens => fileContent.length ~/ 4;

  @override
  ContextPriority get priority => ContextPriority.high;
}

/// Git diff context.
class GitDiffContext extends ContextItem {
  final String diff;
  final String? description;

  GitDiffContext({required this.diff, this.description});

  @override
  String get label => description ?? 'Git diff';

  @override
  String get content =>
      '<git_diff${description != null ? ' description="$description"' : ''}>\n$diff\n</git_diff>';

  @override
  int get estimatedTokens => diff.length ~/ 4;

  @override
  ContextPriority get priority => ContextPriority.medium;
}

/// Search results context.
class SearchResultsContext extends ContextItem {
  final String query;
  final List<SearchHit> hits;

  SearchResultsContext({required this.query, required this.hits});

  @override
  String get label => 'Search: $query';

  @override
  String get content {
    final buffer = StringBuffer();
    buffer.writeln('<search_results query="$query">');
    for (final hit in hits) {
      buffer.writeln('  <result file="${hit.file}" line="${hit.line}">');
      buffer.writeln('    ${hit.content}');
      buffer.writeln('  </result>');
    }
    buffer.writeln('</search_results>');
    return buffer.toString();
  }

  @override
  int get estimatedTokens =>
      hits.fold(0, (sum, h) => sum + h.content.length ~/ 4);

  @override
  ContextPriority get priority => ContextPriority.medium;
}

/// Directory listing context.
class DirectoryContext extends ContextItem {
  final String path;
  final List<String> entries;
  final int depth;

  DirectoryContext({required this.path, required this.entries, this.depth = 2});

  @override
  String get label => 'Directory: ${p.basename(path)}';

  @override
  String get content =>
      '<directory path="$path" depth="$depth">\n${entries.join('\n')}\n</directory>';

  @override
  int get estimatedTokens => entries.length * 5;

  @override
  ContextPriority get priority => ContextPriority.low;
}

/// Project info context.
class ProjectInfoContext extends ContextItem {
  final Map<String, dynamic> info;

  ProjectInfoContext(this.info);

  @override
  String get label => 'Project info';

  @override
  String get content {
    final buffer = StringBuffer();
    buffer.writeln('<project_info>');
    for (final entry in info.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
    buffer.writeln('</project_info>');
    return buffer.toString();
  }

  @override
  int get estimatedTokens => info.length * 10;

  @override
  ContextPriority get priority => ContextPriority.low;
}

/// Memory file context (NEOMAGE.md).
class MemoryContext extends ContextItem {
  final String source; // 'user', 'project', 'parent'
  final String memoryContent;

  MemoryContext({required this.source, required this.memoryContent});

  @override
  String get label => 'Memory ($source)';

  @override
  String get content => '<memory source="$source">\n$memoryContent\n</memory>';

  @override
  int get estimatedTokens => memoryContent.length ~/ 4;

  @override
  ContextPriority get priority => ContextPriority.high;
}

/// Search hit from grep/glob.
class SearchHit {
  final String file;
  final int line;
  final String content;

  const SearchHit({
    required this.file,
    required this.line,
    required this.content,
  });
}

/// Context priority for budget allocation.
enum ContextPriority { critical, high, medium, low }

// ─── Context builder ───

/// Builds optimized context within a token budget.
class ContextBuilder {
  final int tokenBudget;
  final List<ContextItem> _items = [];
  int _usedTokens = 0;

  ContextBuilder({this.tokenBudget = 100000});

  /// Add a context item.
  bool add(ContextItem item) {
    if (_usedTokens + item.estimatedTokens > tokenBudget) {
      return false;
    }
    _items.add(item);
    _usedTokens += item.estimatedTokens;
    return true;
  }

  /// Add a file to context.
  Future<bool> addFile(String path, {int? maxLines}) async {
    final file = File(path);
    if (!await file.exists()) return false;

    final content = await file.readAsString();
    final lines = content.split('\n');
    final truncated = maxLines != null && lines.length > maxLines
        ? '${lines.take(maxLines).join('\n')}\n[... ${lines.length - maxLines} more lines]'
        : content;

    return add(
      FileContext(
        path: path,
        fileContent: truncated,
        language: _detectLanguage(path),
      ),
    );
  }

  /// Add git diff to context.
  Future<bool> addGitDiff({String? ref, bool staged = false}) async {
    try {
      final args = staged
          ? ['diff', '--staged']
          : ref != null
          ? ['diff', ref]
          : ['diff'];

      final result = await Process.run('git', args);
      if (result.exitCode == 0) {
        final diff = (result.stdout as String).trim();
        if (diff.isNotEmpty) {
          return add(
            GitDiffContext(
              diff: diff,
              description: staged
                  ? 'staged changes'
                  : ref != null
                  ? 'diff vs $ref'
                  : 'unstaged changes',
            ),
          );
        }
      }
    } catch (_) {}
    return false;
  }

  /// Add directory listing to context.
  Future<bool> addDirectoryListing(String path, {int depth = 2}) async {
    final entries = <String>[];
    await _listDir(path, entries, depth, 0, '');
    if (entries.isEmpty) return false;
    return add(DirectoryContext(path: path, entries: entries, depth: depth));
  }

  Future<void> _listDir(
    String dirPath,
    List<String> entries,
    int maxDepth,
    int currentDepth,
    String prefix,
  ) async {
    if (currentDepth >= maxDepth) return;

    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    try {
      final items = await dir.list().toList();
      items.sort((a, b) {
        // Dirs first, then files
        final aIsDir = a is Directory ? 0 : 1;
        final bIsDir = b is Directory ? 0 : 1;
        if (aIsDir != bIsDir) return aIsDir.compareTo(bIsDir);
        return p.basename(a.path).compareTo(p.basename(b.path));
      });

      for (final item in items) {
        final name = p.basename(item.path);
        if (name.startsWith('.') ||
            name == 'node_modules' ||
            name == '__pycache__' ||
            name == '.dart_tool') {
          continue;
        }

        if (item is Directory) {
          entries.add('$prefix$name/');
          await _listDir(
            item.path,
            entries,
            maxDepth,
            currentDepth + 1,
            '$prefix  ',
          );
        } else {
          entries.add('$prefix$name');
        }

        if (entries.length > 500) return;
      }
    } catch (_) {}
  }

  /// Add search results to context.
  bool addSearchResults(String query, List<SearchHit> hits) {
    return add(SearchResultsContext(query: query, hits: hits));
  }

  /// Add memory content.
  bool addMemory(String source, String content) {
    if (content.trim().isEmpty) return false;
    return add(MemoryContext(source: source, memoryContent: content));
  }

  /// Build the final context string.
  String build() {
    // Sort by priority
    final sorted = List<ContextItem>.from(_items)
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));

    return sorted.map((item) => item.content).join('\n\n');
  }

  /// Get remaining token budget.
  int get remainingTokens => tokenBudget - _usedTokens;

  /// Get used tokens.
  int get usedTokens => _usedTokens;

  /// Get all items.
  List<ContextItem> get items => List.unmodifiable(_items);

  /// Remove an item.
  void remove(ContextItem item) {
    _items.remove(item);
    _usedTokens -= item.estimatedTokens;
  }

  /// Clear all context.
  void clear() {
    _items.clear();
    _usedTokens = 0;
  }

  /// Detect language from file extension.
  String? _detectLanguage(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    const langMap = {
      'dart': 'dart',
      'ts': 'typescript',
      'tsx': 'typescript',
      'js': 'javascript',
      'jsx': 'javascript',
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
      'json': 'json',
      'yaml': 'yaml',
      'yml': 'yaml',
      'xml': 'xml',
      'md': 'markdown',
      'sql': 'sql',
      'sh': 'bash',
      'bash': 'bash',
    };
    return langMap[ext];
  }
}

// ─── Auto-context ───

/// Automatically gather relevant context for a user query.
Future<String> gatherAutoContext({
  required String query,
  required String workingDirectory,
  int tokenBudget = 50000,
  List<String> mentionedFiles = const [],
}) async {
  final builder = ContextBuilder(tokenBudget: tokenBudget);

  // 1. Add explicitly mentioned files (highest priority)
  for (final file in mentionedFiles) {
    final resolved = p.isAbsolute(file) ? file : p.join(workingDirectory, file);
    await builder.addFile(resolved, maxLines: 500);
  }

  // 2. Add project info
  final projectInfo = await _detectProjectInfo(workingDirectory);
  if (projectInfo.isNotEmpty) {
    builder.add(ProjectInfoContext(projectInfo));
  }

  // 3. Add git status/diff if relevant
  if (_queryRelatesTo(query, ['diff', 'change', 'commit', 'git', 'modified'])) {
    await builder.addGitDiff();
    await builder.addGitDiff(staged: true);
  }

  // 4. Add directory listing if relevant
  if (_queryRelatesTo(query, [
    'file',
    'directory',
    'structure',
    'project',
    'where',
  ])) {
    await builder.addDirectoryListing(workingDirectory);
  }

  return builder.build();
}

bool _queryRelatesTo(String query, List<String> keywords) {
  final lower = query.toLowerCase();
  return keywords.any((k) => lower.contains(k));
}

Future<Map<String, dynamic>> _detectProjectInfo(String dir) async {
  final info = <String, dynamic>{};
  info['workingDirectory'] = dir;

  // Detect package manager and language
  final checks = {
    'pubspec.yaml': {'language': 'dart', 'framework': 'flutter'},
    'package.json': {
      'language': 'javascript/typescript',
      'packageManager': 'npm',
    },
    'Cargo.toml': {'language': 'rust', 'packageManager': 'cargo'},
    'go.mod': {'language': 'go', 'packageManager': 'go mod'},
    'requirements.txt': {'language': 'python', 'packageManager': 'pip'},
    'Gemfile': {'language': 'ruby', 'packageManager': 'bundler'},
    'pom.xml': {'language': 'java', 'packageManager': 'maven'},
    'build.gradle': {'language': 'java/kotlin', 'packageManager': 'gradle'},
  };

  for (final entry in checks.entries) {
    if (await File(p.join(dir, entry.key)).exists()) {
      info.addAll(entry.value);
      break;
    }
  }

  // Check git
  try {
    final gitResult = await Process.run('git', [
      'rev-parse',
      '--show-toplevel',
    ], workingDirectory: dir);
    if (gitResult.exitCode == 0) {
      info['gitRoot'] = (gitResult.stdout as String).trim();
      final branchResult = await Process.run('git', [
        'branch',
        '--show-current',
      ], workingDirectory: dir);
      if (branchResult.exitCode == 0) {
        info['gitBranch'] = (branchResult.stdout as String).trim();
      }
    }
  } catch (_) {}

  return info;
}
