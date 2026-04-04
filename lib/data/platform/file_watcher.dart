// File watcher service — port of neom_claw chokidar-based file watching.
// Watches files and directories for changes with debouncing.

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';

/// File change event types.
enum FileChangeType { created, modified, deleted }

/// A file change event.
class FileChange {
  final String path;
  final FileChangeType type;
  final DateTime timestamp;

  FileChange({required this.path, required this.type})
    : timestamp = DateTime.now();

  @override
  String toString() => 'FileChange(${type.name}: $path)';
}

/// A file watcher subscription.
class WatchSubscription {
  final String id;
  final String path;
  final StreamSubscription<FileSystemEvent> _subscription;
  bool _active = true;

  WatchSubscription._({
    required this.id,
    required this.path,
    required StreamSubscription<FileSystemEvent> subscription,
  }) : _subscription = subscription;

  bool get isActive => _active;

  Future<void> cancel() async {
    _active = false;
    await _subscription.cancel();
  }
}

/// File watcher service — watches files and directories for changes.
class FileWatcherService {
  final Map<String, WatchSubscription> _subscriptions = {};
  final Duration _debounceDelay;
  final Map<String, Timer> _debounceTimers = {};
  int _nextId = 0;

  FileWatcherService({
    Duration debounceDelay = const Duration(milliseconds: 300),
  }) : _debounceDelay = debounceDelay;

  /// Watch a file for changes.
  Future<String?> watchFile(
    String filePath,
    void Function(FileChange) callback,
  ) async {
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final parent = file.parent;
    final fileName = file.uri.pathSegments.last;
    final id = 'watch_${_nextId++}';

    try {
      final stream = parent.watch(events: FileSystemEvent.all);
      final sub = stream.listen((event) {
        if (!event.path.endsWith(fileName)) return;
        _handleEvent(id, event, callback);
      });

      _subscriptions[id] = WatchSubscription._(
        id: id,
        path: filePath,
        subscription: sub,
      );

      return id;
    } catch (_) {
      return null;
    }
  }

  /// Watch a directory for changes.
  Future<String?> watchDirectory(
    String dirPath,
    void Function(FileChange) callback, {
    bool recursive = true,
    List<String> extensions = const [],
    List<String> ignorePatterns = const [],
  }) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    final id = 'watch_${_nextId++}';

    try {
      final stream = dir.watch(
        events: FileSystemEvent.all,
        recursive: recursive,
      );

      final sub = stream.listen((event) {
        // Filter by extension
        if (extensions.isNotEmpty) {
          final hasMatchingExt = extensions.any(
            (ext) => event.path.endsWith(ext),
          );
          if (!hasMatchingExt) return;
        }

        // Filter by ignore patterns
        if (ignorePatterns.isNotEmpty) {
          final shouldIgnore = ignorePatterns.any(
            (pattern) => event.path.contains(pattern),
          );
          if (shouldIgnore) return;
        }

        _handleEvent(id, event, callback);
      });

      _subscriptions[id] = WatchSubscription._(
        id: id,
        path: dirPath,
        subscription: sub,
      );

      return id;
    } catch (_) {
      return null;
    }
  }

  /// Watch for config file changes (~/.neomclaw/settings.json, etc.).
  Future<String?> watchConfig(
    String configPath,
    void Function(FileChange) callback,
  ) async {
    return watchFile(configPath, callback);
  }

  /// Watch for keybinding file changes.
  Future<String?> watchKeybindings(
    String keybindingsPath,
    void Function(FileChange) callback,
  ) async {
    return watchFile(keybindingsPath, callback);
  }

  /// Cancel a specific watch.
  Future<void> unwatch(String id) async {
    final sub = _subscriptions.remove(id);
    if (sub != null) {
      await sub.cancel();
    }
    _debounceTimers.remove(id)?.cancel();
  }

  /// Cancel all watches.
  Future<void> unwatchAll() async {
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    _subscriptions.clear();
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  /// Active watch count.
  int get activeWatches =>
      _subscriptions.values.where((s) => s.isActive).length;

  /// All watched paths.
  List<String> get watchedPaths =>
      _subscriptions.values.map((s) => s.path).toList();

  void dispose() {
    unwatchAll();
  }

  // ── Private ──

  void _handleEvent(
    String watchId,
    FileSystemEvent event,
    void Function(FileChange) callback,
  ) {
    final type = switch (event.type) {
      FileSystemEvent.create => FileChangeType.created,
      FileSystemEvent.modify => FileChangeType.modified,
      FileSystemEvent.delete => FileChangeType.deleted,
      FileSystemEvent.move => FileChangeType.modified,
      _ => FileChangeType.modified,
    };

    final change = FileChange(path: event.path, type: type);

    // Debounce: cancel existing timer and set new one
    final key = '$watchId:${event.path}';
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(_debounceDelay, () {
      callback(change);
      _debounceTimers.remove(key);
    });
  }
}

/// Common ignore patterns for file watching.
const defaultIgnorePatterns = [
  '.git/',
  'node_modules/',
  '.dart_tool/',
  'build/',
  '.idea/',
  '.vscode/',
  '__pycache__/',
  '.DS_Store',
  'thumbs.db',
];
