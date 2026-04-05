import 'package:neomage/core/platform/neomage_io.dart';

import 'tool.dart';

/// Find files by pattern — port of neomage/src/tools/GlobTool.
class GlobTool extends Tool with ReadOnlyToolMixin {
  @override
  String get name => 'Glob';

  @override
  String get description =>
      'Fast file pattern matching tool that works with any codebase size.\n\n'
      '- Supports glob patterns like "**/*.js" or "src/**/*.ts".\n'
      '- Returns matching file paths sorted by modification time.\n'
      '- Use this tool when you need to find files by name patterns.\n'
      '- When doing an open-ended search that may require multiple rounds of '
      'globbing and grepping, use the Agent tool instead.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'pattern': {
        'type': 'string',
        'description': 'Glob pattern to match (e.g. "**/*.dart")',
      },
      'path': {
        'type': 'string',
        'description': 'Directory to search in (default: current directory)',
      },
    },
    'required': ['pattern'],
  };

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final pattern = input['pattern'] as String?;
    if (pattern == null || pattern.isEmpty) {
      return ToolResult.error('Missing required parameter: pattern');
    }

    final searchPath = input['path'] as String? ?? Directory.current.path;
    final dir = Directory(searchPath);

    if (!await dir.exists()) {
      return ToolResult.error('Directory not found: $searchPath');
    }

    try {
      // Extract extension from glob pattern
      final ext = _extractExtension(pattern);
      final matches = <_FileMatch>[];

      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (_shouldSkip(entity.path)) continue;

        if (ext != null && !entity.path.endsWith(ext)) continue;
        if (ext == null && !_simpleGlobMatch(entity.path, pattern)) continue;

        final stat = await entity.stat();
        matches.add(_FileMatch(entity.path, stat.modified));

        if (matches.length >= 500) break;
      }

      // Sort by modification time (newest first)
      matches.sort((a, b) => b.modified.compareTo(a.modified));

      if (matches.isEmpty) {
        return ToolResult.success('No files matching pattern: $pattern');
      }

      return ToolResult.success(matches.map((m) => m.path).join('\n'));
    } catch (e) {
      return ToolResult.error('Glob error: $e');
    }
  }

  String? _extractExtension(String pattern) {
    final match = RegExp(r'\*\.(\w+)$').firstMatch(pattern);
    return match != null ? '.${match.group(1)}' : null;
  }

  bool _simpleGlobMatch(String path, String pattern) {
    final regexPattern = pattern
        .replaceAll('.', r'\.')
        .replaceAll('**/', '(.+/)?')
        .replaceAll('*', '[^/]*')
        .replaceAll('?', '[^/]');
    return RegExp(regexPattern).hasMatch(path);
  }

  bool _shouldSkip(String path) {
    const skipDirs = ['.git', 'node_modules', '.dart_tool', 'build', '.pub'];
    return skipDirs.any((d) => path.contains('/$d/'));
  }
}

class _FileMatch {
  final String path;
  final DateTime modified;
  _FileMatch(this.path, this.modified);
}
