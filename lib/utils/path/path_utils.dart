/// Path manipulation utilities ported from NeomClaw TypeScript.
///
/// Provides path normalization, glob matching, gitignore parsing,
/// prefix-based trie lookup, and file system watching primitives.
library;

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// Core path helpers
// ---------------------------------------------------------------------------

/// Normalizes a file-system path by collapsing separators, resolving `.` and
/// `..` segments, and converting backslashes to forward slashes.
String normalizePath(String path) {
  if (path.isEmpty) return '.';

  // Convert backslashes to forward slashes.
  var p = path.replaceAll('\\', '/');

  // Preserve leading double-slash (UNC on Windows).
  final isUnc = p.startsWith('//');

  // Collapse consecutive slashes.
  p = p.replaceAll(RegExp(r'/+'), '/');
  if (isUnc) p = '/$p';

  final isAbs = p.startsWith('/');
  final segments = p.split('/');
  final resolved = <String>[];

  for (final seg in segments) {
    if (seg == '.' || seg.isEmpty) {
      continue;
    } else if (seg == '..') {
      if (resolved.isNotEmpty && resolved.last != '..') {
        resolved.removeLast();
      } else if (!isAbs) {
        resolved.add('..');
      }
    } else {
      resolved.add(seg);
    }
  }

  var result = resolved.join('/');
  if (isAbs) result = '/$result';
  if (result.isEmpty) return isAbs ? '/' : '.';
  return result;
}

/// Computes the relative path from [from] to [to].
///
/// Both paths are normalized before computation. If a relative path cannot be
/// constructed (e.g. different drive letters on Windows), [to] is returned
/// unchanged.
String relativePath(String from, String to) {
  final nFrom = normalizePath(from).split('/');
  final nTo = normalizePath(to).split('/');

  // Find the common prefix length.
  var common = 0;
  while (common < nFrom.length &&
      common < nTo.length &&
      nFrom[common] == nTo[common]) {
    common++;
  }

  final ups = List.filled(nFrom.length - common, '..');
  final tail = nTo.sublist(common);
  final parts = [...ups, ...tail];
  if (parts.isEmpty) return '.';
  return parts.join('/');
}

/// Expands a leading `~` to the current user's home directory.
String expandHome(String path) {
  if (!path.startsWith('~')) return path;
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (path == '~') return home;
  if (path.startsWith('~/') || path.startsWith('~\\')) {
    return '$home${path.substring(1)}';
  }
  return path;
}

/// Returns `true` if [path] is an absolute path.
bool isAbsolute(String path) {
  if (path.isEmpty) return false;
  if (path.startsWith('/')) return true;
  // Windows drive letter: C:\ or C:/
  if (path.length >= 3 && RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(path)) {
    return true;
  }
  return false;
}

/// Joins path [parts] with the platform separator, normalizing the result.
String joinPaths(List<String> parts) {
  if (parts.isEmpty) return '.';
  return normalizePath(parts.where((p) => p.isNotEmpty).join('/'));
}

/// Splits [path] into `(directory, basename, extension)`.
///
/// ```dart
/// splitPath('/foo/bar.txt') => ('/foo', 'bar', '.txt')
/// ```
({String dir, String basename, String ext}) splitPath(String path) {
  final normalized = normalizePath(path);
  final lastSlash = normalized.lastIndexOf('/');
  final dir = lastSlash == -1 ? '.' : normalized.substring(0, lastSlash);
  final file = lastSlash == -1
      ? normalized
      : normalized.substring(lastSlash + 1);
  final dotIdx = file.lastIndexOf('.');
  if (dotIdx <= 0) {
    return (dir: dir, basename: file, ext: '');
  }
  return (
    dir: dir,
    basename: file.substring(0, dotIdx),
    ext: file.substring(dotIdx),
  );
}

/// Returns the file extension of [path] including the dot, or empty string.
String getExtension(String path) => splitPath(path).ext;

/// Returns [path] with its extension changed to [newExt].
///
/// [newExt] should include the leading dot (e.g. `.dart`).
String changeExtension(String path, String newExt) {
  final parts = splitPath(path);
  return joinPaths([parts.dir, '${parts.basename}$newExt']);
}

/// Returns `true` if [child] is a sub-path of [parent].
bool isSubPath(String parent, String child) {
  final np = normalizePath(parent);
  final nc = normalizePath(child);
  if (nc == np) return true;
  return nc.startsWith('$np/');
}

/// Finds the longest common ancestor directory of the given [paths].
///
/// Returns `'.'` when no common ancestor exists.
String findCommonAncestor(List<String> paths) {
  if (paths.isEmpty) return '.';
  if (paths.length == 1) return splitPath(paths.first).dir;

  final split = paths.map((p) => normalizePath(p).split('/')).toList();
  final minLen = split.map((s) => s.length).reduce((a, b) => a < b ? a : b);
  final common = <String>[];
  for (var i = 0; i < minLen; i++) {
    final seg = split.first[i];
    if (split.every((s) => s[i] == seg)) {
      common.add(seg);
    } else {
      break;
    }
  }
  if (common.isEmpty) return '.';
  final result = common.join('/');
  return result.isEmpty ? '.' : result;
}

/// Converts a file-system [path] to a `file://` [Uri].
Uri toUri(String path) {
  final normalized = normalizePath(expandHome(path));
  return Uri.file(normalized);
}

/// Converts a `file://` [uri] back to a platform path string.
String fromUri(Uri uri) => uri.toFilePath();

/// Returns `true` when the final component of [path] starts with `.`.
bool isHidden(String path) {
  final parts = splitPath(path);
  final name = '${parts.basename}${parts.ext}';
  return name.startsWith('.');
}

/// Removes dangerous characters from [path] that could cause security issues.
///
/// Strips null bytes, path traversal sequences, and control characters.
String sanitizePath(String path) {
  var p = path;
  // Remove null bytes.
  p = p.replaceAll('\x00', '');
  // Remove control characters (0x01-0x1F, 0x7F) except tab/newline.
  p = p.replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  // Collapse path traversal.
  while (p.contains('..')) {
    p = p.replaceAll('..', '');
  }
  // Remove leading/trailing whitespace from each segment.
  p = p.split('/').map((s) => s.trim()).where((s) => s.isNotEmpty).join('/');
  // Preserve leading slash.
  if (path.startsWith('/') && !p.startsWith('/')) {
    p = '/$p';
  }
  return p;
}

// ---------------------------------------------------------------------------
// GlobMatcher
// ---------------------------------------------------------------------------

/// Compiles shell-style glob patterns to [RegExp] and matches paths.
class GlobMatcher {
  GlobMatcher._(this._pattern, this._regex);

  final String _pattern;
  final RegExp _regex;

  /// Compiles a glob [pattern] into a [GlobMatcher].
  ///
  /// Supported syntax:
  /// - `*`  matches any characters except `/`
  /// - `**` matches any characters including `/`
  /// - `?`  matches exactly one character except `/`
  /// - `[abc]` character class
  /// - `{a,b}` alternation
  factory GlobMatcher.compile(String pattern) {
    final regex = _globToRegex(pattern);
    return GlobMatcher._(pattern, RegExp('^$regex\$'));
  }

  /// Returns `true` if [path] matches this glob pattern.
  bool match(String path) => _regex.hasMatch(normalizePath(path));

  /// Filters [paths], returning only those that match.
  List<String> matchAll(List<String> paths) => paths.where(match).toList();

  /// The original glob pattern string.
  String get pattern => _pattern;

  static String _globToRegex(String glob) {
    final buf = StringBuffer();
    var i = 0;
    while (i < glob.length) {
      final c = glob[i];
      switch (c) {
        case '*':
          if (i + 1 < glob.length && glob[i + 1] == '*') {
            // ** — match everything including separators.
            buf.write('.*');
            i += 2;
            // Consume trailing slash after **.
            if (i < glob.length && glob[i] == '/') i++;
          } else {
            buf.write(r'[^/]*');
            i++;
          }
          break;
        case '?':
          buf.write(r'[^/]');
          i++;
          break;
        case '[':
          final end = glob.indexOf(']', i);
          if (end == -1) {
            buf.write(r'\[');
            i++;
          } else {
            buf.write('[');
            buf.write(glob.substring(i + 1, end));
            buf.write(']');
            i = end + 1;
          }
          break;
        case '{':
          final end = glob.indexOf('}', i);
          if (end == -1) {
            buf.write(r'\{');
            i++;
          } else {
            final options = glob.substring(i + 1, end).split(',');
            buf.write('(?:');
            buf.write(options.map(_globToRegex).join('|'));
            buf.write(')');
            i = end + 1;
          }
          break;
        case '.':
        case '+':
        case '^':
        case r'$':
        case '(':
        case ')':
        case '|':
        case '\\':
          buf.write('\\$c');
          i++;
          break;
        default:
          buf.write(c);
          i++;
      }
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// GitignoreParser
// ---------------------------------------------------------------------------

/// Parses `.gitignore`-style patterns and determines whether paths are ignored.
class GitignoreParser {
  GitignoreParser._(this._rules);

  final List<_GitignoreRule> _rules;

  /// Parses gitignore [content] (the text of a `.gitignore` file).
  factory GitignoreParser.parse(String content) {
    final rules = <_GitignoreRule>[];
    for (var line in content.split('\n')) {
      line = line.trimRight();
      if (line.isEmpty || line.startsWith('#')) continue;
      final negated = line.startsWith('!');
      if (negated) line = line.substring(1);
      final dirOnly = line.endsWith('/');
      if (dirOnly) line = line.substring(0, line.length - 1);
      rules.add(
        _GitignoreRule(
          pattern: GlobMatcher.compile(line),
          negated: negated,
          directoryOnly: dirOnly,
        ),
      );
    }
    return GitignoreParser._(rules);
  }

  /// Loads and parses a `.gitignore` file at [path].
  ///
  /// Returns an empty parser if the file does not exist.
  static Future<GitignoreParser> loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return GitignoreParser._([]);
    final content = await file.readAsString();
    return GitignoreParser.parse(content);
  }

  /// Returns `true` if the given [path] would be ignored by the parsed rules.
  ///
  /// If [isDirectory] is `true`, directory-only rules are considered.
  bool isIgnored(String path, {bool isDirectory = false}) {
    var ignored = false;
    for (final rule in _rules) {
      if (rule.directoryOnly && !isDirectory) continue;
      if (rule.pattern.match(path)) {
        ignored = !rule.negated;
      }
    }
    return ignored;
  }
}

class _GitignoreRule {
  const _GitignoreRule({
    required this.pattern,
    required this.negated,
    required this.directoryOnly,
  });

  final GlobMatcher pattern;
  final bool negated;
  final bool directoryOnly;
}

// ---------------------------------------------------------------------------
// PathTrie
// ---------------------------------------------------------------------------

/// Efficient prefix-based path lookup using a trie structure.
///
/// Each node corresponds to a single path segment. Values of type [T] can be
/// stored at any node.
class PathTrie<T> {
  final _TrieNode<T> _root = _TrieNode<T>();

  /// Inserts [value] at the given [path].
  void insert(String path, T value) {
    final segments = _segments(path);
    var node = _root;
    for (final seg in segments) {
      node = node.children.putIfAbsent(seg, _TrieNode.new);
    }
    node.value = value;
    node.hasValue = true;
  }

  /// Looks up the value stored at [path], or `null` if none.
  T? lookup(String path) {
    final segments = _segments(path);
    var node = _root;
    for (final seg in segments) {
      final child = node.children[seg];
      if (child == null) return null;
      node = child;
    }
    return node.hasValue ? node.value : null;
  }

  /// Removes the value stored at [path]. Returns `true` if a value existed.
  bool remove(String path) {
    final segments = _segments(path);
    var node = _root;
    final stack = <(String, _TrieNode<T>)>[];
    for (final seg in segments) {
      stack.add((seg, node));
      final child = node.children[seg];
      if (child == null) return false;
      node = child;
    }
    if (!node.hasValue) return false;
    node
      ..value = null
      ..hasValue = false;

    // Prune empty leaf nodes.
    for (var i = stack.length - 1; i >= 0; i--) {
      final (seg, parent) = stack[i];
      final child = parent.children[seg]!;
      if (!child.hasValue && child.children.isEmpty) {
        parent.children.remove(seg);
      } else {
        break;
      }
    }
    return true;
  }

  /// Returns all `(path, value)` pairs whose path starts with [prefix].
  List<(String, T)> findByPrefix(String prefix) {
    final segments = _segments(prefix);
    var node = _root;
    for (final seg in segments) {
      final child = node.children[seg];
      if (child == null) return [];
      node = child;
    }
    final results = <(String, T)>[];
    _collect(node, segments, results);
    return results;
  }

  void _collect(
    _TrieNode<T> node,
    List<String> path,
    List<(String, T)> results,
  ) {
    if (node.hasValue) {
      results.add((path.join('/'), node.value as T));
    }
    for (final entry in node.children.entries) {
      _collect(entry.value, [...path, entry.key], results);
    }
  }

  List<String> _segments(String path) =>
      normalizePath(path).split('/').where((s) => s.isNotEmpty).toList();
}

class _TrieNode<T> {
  final Map<String, _TrieNode<T>> children = {};
  T? value;
  bool hasValue = false;
}

// ---------------------------------------------------------------------------
// FileWatcher
// ---------------------------------------------------------------------------

/// Configuration for [FileWatcher].
class WatcherConfig {
  const WatcherConfig({
    this.debounce = const Duration(milliseconds: 200),
    this.recursive = true,
    this.filters = const [],
    this.ignoreHidden = true,
    this.ignorePatterns = const [],
  });

  /// Minimum time between emitted events for the same path.
  final Duration debounce;

  /// Whether to watch subdirectories recursively.
  final bool recursive;

  /// If non-empty, only events for paths matching one of these extensions
  /// (e.g. `.dart`, `.ts`) will be emitted.
  final List<String> filters;

  /// If `true`, hidden files (starting with `.`) are ignored.
  final bool ignoreHidden;

  /// Glob patterns for paths to ignore entirely.
  final List<String> ignorePatterns;
}

/// The type of file system change observed.
enum FileEventType { create, modify, delete, rename }

/// A file system event emitted by [FileWatcher].
class FileEvent {
  const FileEvent({
    required this.type,
    required this.path,
    required this.timestamp,
  });

  final FileEventType type;
  final String path;
  final DateTime timestamp;

  @override
  String toString() => 'FileEvent($type, $path)';
}

/// Watches a file or directory for changes, emitting [FileEvent]s.
class FileWatcher {
  FileWatcher._();

  static final FileWatcher _instance = FileWatcher._();

  /// Returns the singleton [FileWatcher] instance.
  factory FileWatcher() => _instance;

  final Map<String, StreamSubscription<FileSystemEvent>> _subscriptions = {};

  /// Starts watching [path] with the provided [config].
  ///
  /// Returns a broadcast [Stream] of [FileEvent]s. Only one watcher per path
  /// is active at a time; calling [watch] again for the same path replaces the
  /// previous watcher.
  Stream<FileEvent> watch(
    String path, {
    WatcherConfig config = const WatcherConfig(),
  }) {
    // Cancel existing watcher for this path.
    _subscriptions[path]?.cancel();

    final controller = StreamController<FileEvent>.broadcast();
    final compiledIgnore = config.ignorePatterns
        .map(GlobMatcher.compile)
        .toList();

    final entity = FileSystemEntity.isDirectorySync(path)
        ? Directory(path)
        : File(path);

    // Debounce tracking.
    final lastEmit = <String, DateTime>{};

    final sub = entity.watch(recursive: config.recursive).listen((fse) {
      final eventPath = normalizePath(fse.path);

      // Filter by extension.
      if (config.filters.isNotEmpty) {
        final ext = getExtension(eventPath);
        if (!config.filters.contains(ext)) return;
      }

      // Ignore hidden.
      if (config.ignoreHidden && isHidden(eventPath)) return;

      // Ignore patterns.
      for (final glob in compiledIgnore) {
        if (glob.match(eventPath)) return;
      }

      // Debounce.
      final now = DateTime.now();
      final last = lastEmit[eventPath];
      if (last != null && now.difference(last) < config.debounce) return;
      lastEmit[eventPath] = now;

      final type = switch (fse.type) {
        FileSystemEvent.create => FileEventType.create,
        FileSystemEvent.modify => FileEventType.modify,
        FileSystemEvent.delete => FileEventType.delete,
        FileSystemEvent.move => FileEventType.rename,
        _ => FileEventType.modify,
      };

      controller.add(FileEvent(type: type, path: eventPath, timestamp: now));
    });

    _subscriptions[path] = sub;

    // Clean up when the controller has no listeners.
    controller.onCancel = () {
      sub.cancel();
      _subscriptions.remove(path);
    };

    return controller.stream;
  }

  /// Stops all active watchers.
  Future<void> stopAll() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
