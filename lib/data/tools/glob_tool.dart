import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';
import 'package:path/path.dart' as p;

import 'tool.dart';

/// Maximum entities visited per glob scan to bound traversal latency/memory.
const int maxGlobVisitedEntities = 50000;

/// Maximum glob pattern length.
const int maxGlobPatternLength = 1024;

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
  ValidationResult validateInput(Map<String, dynamic> input) {
    final pattern = input['pattern'] as String?;
    if (pattern == null || pattern.isEmpty) {
      return const ValidationResult.invalid(
        'Missing required parameter: pattern',
      );
    }
    if (pattern.contains('\x00')) {
      return const ValidationResult.invalid('Invalid NUL byte in pattern');
    }
    if (pattern.length > maxGlobPatternLength) {
      return const ValidationResult.invalid(
        'Pattern exceeds maximum length ($maxGlobPatternLength chars)',
      );
    }

    final rawPath = input['path'] as String?;
    if (rawPath != null && rawPath.isNotEmpty) {
      if (rawPath.contains('\x00')) {
        return const ValidationResult.invalid('Invalid NUL byte in path');
      }
      if (rawPath.startsWith(r'\\') || rawPath.startsWith('//')) {
        return const ValidationResult.invalid(
          'UNC network paths are blocked to prevent NTLM credential leaks',
        );
      }
      final expanded = _expandSearchPath(rawPath);
      if (expanded.startsWith(r'\\') || expanded.startsWith('//')) {
        return const ValidationResult.invalid(
          'UNC network paths are blocked to prevent NTLM credential leaks',
        );
      }
      final protectedReason = NeomageNetworkGuard.checkProtectedFilesystemPath(
        p.normalize(expanded),
      );
      if (protectedReason != null) {
        return ValidationResult.invalid(protectedReason);
      }
    }

    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) {
      return ToolResult.error(validation.error ?? 'Invalid glob input');
    }

    final pattern = input['pattern'] as String;
    final rawPath = input['path'] as String?;
    final searchPath = rawPath != null && rawPath.isNotEmpty
        ? _expandSearchPath(rawPath)
        : Directory.current.path;

    final protectedReason = NeomageNetworkGuard.checkProtectedFilesystemPath(
      p.normalize(searchPath),
    );
    if (protectedReason != null) {
      return ToolResult.error(protectedReason);
    }

    final dir = Directory(searchPath);
    if (!await dir.exists()) {
      return ToolResult.error('Directory not found: ${rawPath ?? searchPath}');
    }

    try {
      final resolvedRoot = await dir.resolveSymbolicLinks();
      final resolvedProtected =
          NeomageNetworkGuard.checkProtectedFilesystemPath(
            p.normalize(resolvedRoot),
          );
      if (resolvedProtected != null) {
        return ToolResult.error(resolvedProtected);
      }

      // Extract simple extension when pattern has no directory constraints
      final ext = _extractExtension(pattern);
      final compiledRegex = ext == null ? _compileGlobRegex(pattern) : null;
      final matches = <_FileMatch>[];
      var visited = 0;

      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        visited++;
        if (visited > maxGlobVisitedEntities) break;
        if (entity is! File) continue;
        if (_shouldSkip(entity.path)) continue;

        final normalizedEntityPath = entity.path.replaceAll(r'\', '/');
        if (ext != null && !normalizedEntityPath.endsWith(ext)) continue;
        if (compiledRegex != null &&
            !compiledRegex.hasMatch(normalizedEntityPath)) {
          continue;
        }

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

  String _expandSearchPath(String rawPath) {
    if (rawPath == '~' || rawPath.startsWith('~/')) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      return p.join(home, rawPath.substring(rawPath.startsWith('~/') ? 2 : 1));
    }
    if (!p.isAbsolute(rawPath)) {
      return p.join(Directory.current.path, rawPath);
    }
    return rawPath;
  }

  String? _extractExtension(String pattern) {
    final match = RegExp(r'^(?:\*\*/)?\*\.(\w+)$').firstMatch(pattern);
    return match != null ? '.${match.group(1)}' : null;
  }

  RegExp _compileGlobRegex(String pattern) {
    final normalized = pattern.replaceAll(r'\', '/');
    final buf = StringBuffer();
    for (var i = 0; i < normalized.length; i++) {
      final ch = normalized[i];
      if (ch == '*') {
        if (i + 1 < normalized.length && normalized[i + 1] == '*') {
          if (i + 2 < normalized.length && normalized[i + 2] == '/') {
            buf.write('(?:.+/)?');
            i += 2;
          } else {
            buf.write('.*');
            i += 1;
          }
        } else {
          buf.write('[^/]*');
        }
      } else if (ch == '?') {
        buf.write('[^/]');
      } else if (r'\^$.|+()[]{}'.contains(ch)) {
        buf.write(r'\');
        buf.write(ch);
      } else {
        buf.write(ch);
      }
    }
    return RegExp(buf.toString());
  }

  bool _shouldSkip(String path) {
    final normalized = path.replaceAll(r'\', '/');
    const skipDirs = ['.git', 'node_modules', '.dart_tool', 'build', '.pub'];
    return skipDirs.any(
      (d) => normalized.contains('/$d/') || normalized.startsWith('$d/'),
    );
  }
}

class _FileMatch {
  final String path;
  final DateTime modified;
  _FileMatch(this.path, this.modified);
}
