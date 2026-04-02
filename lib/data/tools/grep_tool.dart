import 'dart:io';

import 'tool.dart';

/// Search file contents with regex — port of openclaude/src/tools/GrepTool.
class GrepTool extends Tool with ReadOnlyToolMixin {
  @override
  String get name => 'Grep';

  @override
  String get description =>
      'Searches for a pattern in file contents using regular expressions. '
      'Returns matching file paths or content lines.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'pattern': {
            'type': 'string',
            'description': 'The regex pattern to search for',
          },
          'path': {
            'type': 'string',
            'description':
                'Directory or file to search in (default: current directory)',
          },
          'glob': {
            'type': 'string',
            'description': 'Glob pattern to filter files (e.g. "*.dart")',
          },
          'case_insensitive': {
            'type': 'boolean',
            'description': 'Case insensitive search (default: false)',
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
    final caseInsensitive = input['case_insensitive'] as bool? ?? false;

    try {
      final regex = RegExp(pattern, caseSensitive: !caseInsensitive);
      final dir = Directory(searchPath);

      if (!await dir.exists()) {
        // Try as file
        final file = File(searchPath);
        if (await file.exists()) {
          return _searchFile(file, regex);
        }
        return ToolResult.error('Path not found: $searchPath');
      }

      final results = <String>[];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (_shouldSkip(entity.path)) continue;

        final globPattern = input['glob'] as String?;
        if (globPattern != null && !_matchesGlob(entity.path, globPattern)) {
          continue;
        }

        try {
          final content = await entity.readAsString();
          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (regex.hasMatch(lines[i])) {
              results.add('${entity.path}:${i + 1}:${lines[i]}');
            }
          }
        } catch (_) {
          // Skip binary files
        }

        if (results.length >= 250) break;
      }

      if (results.isEmpty) {
        return ToolResult.success('No matches found');
      }
      return ToolResult.success(results.join('\n'));
    } catch (e) {
      return ToolResult.error('Search error: $e');
    }
  }

  Future<ToolResult> _searchFile(File file, RegExp regex) async {
    final lines = await file.readAsLines();
    final results = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (regex.hasMatch(lines[i])) {
        results.add('${i + 1}:${lines[i]}');
      }
    }
    if (results.isEmpty) return ToolResult.success('No matches found');
    return ToolResult.success(results.join('\n'));
  }

  bool _shouldSkip(String path) {
    const skipDirs = ['.git', 'node_modules', '.dart_tool', 'build', '.pub'];
    return skipDirs.any((d) => path.contains('/$d/'));
  }

  bool _matchesGlob(String path, String glob) {
    final ext = glob.replaceAll('*', '');
    return path.endsWith(ext);
  }
}
