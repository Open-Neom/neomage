// Clipboard service — port of neom_claw clipboard management.
// Provides clipboard ring, history, system clipboard integration,
// and specialised copy operations for code, diffs, and tool output.

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Source that produced a clipboard entry.
enum ClipboardSource {
  /// Copied by a tool action.
  tool,

  /// Copied by the user.
  user,

  /// Copied by the system / internal operation.
  system,
}

/// Type of content stored in a clipboard entry.
enum ClipboardContentType {
  /// Plain text.
  text,

  /// Source code.
  code,

  /// Diff / patch output.
  diff,

  /// File path.
  path,
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A single entry in the clipboard history.
class ClipboardEntry {
  /// The text content.
  final String content;

  /// When the entry was created.
  final DateTime timestamp;

  /// Where the content originated.
  final ClipboardSource source;

  /// What kind of content this is.
  final ClipboardContentType contentType;

  /// Optional label for display purposes.
  final String? label;

  const ClipboardEntry({
    required this.content,
    required this.timestamp,
    required this.source,
    required this.contentType,
    this.label,
  });

  /// A short preview of the content (first line, truncated).
  String get preview {
    final firstLine = content.split('\n').first;
    return firstLine.length > 80
        ? '${firstLine.substring(0, 80)}...'
        : firstLine;
  }

  @override
  String toString() => '[$contentType] $preview';
}

/// A ring buffer of clipboard entries that supports cycling through past
/// copies.
class ClipboardRing {
  /// Maximum number of entries the ring will hold.
  final int maxSize;

  final List<ClipboardEntry> _entries = [];
  int _currentIndex = -1;

  ClipboardRing({this.maxSize = 30});

  /// All entries in the ring (most recent first).
  List<ClipboardEntry> get entries => List.unmodifiable(_entries.reversed);

  /// Number of entries currently stored.
  int get length => _entries.length;

  /// Whether the ring is empty.
  bool get isEmpty => _entries.isEmpty;

  /// The entry at the current ring position, or null if empty.
  ClipboardEntry? get current =>
      _entries.isEmpty ? null : _entries[_currentIndex];

  /// Add a new entry to the ring. Resets the current index to the newest
  /// entry.
  void add(ClipboardEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxSize) {
      _entries.removeAt(0);
    }
    _currentIndex = _entries.length - 1;
  }

  /// Cycle to the next (older) entry and return it.
  ///
  /// Wraps around to the newest entry after reaching the oldest.
  ClipboardEntry? paste() {
    if (_entries.isEmpty) return null;
    final entry = _entries[_currentIndex];
    _currentIndex = (_currentIndex - 1) % _entries.length;
    if (_currentIndex < 0) _currentIndex = _entries.length - 1;
    return entry;
  }

  /// Return the entry at [index] (0 = most recent).
  ClipboardEntry? entryAt(int index) {
    if (index < 0 || index >= _entries.length) return null;
    return _entries[_entries.length - 1 - index];
  }

  /// Remove all entries.
  void clear() {
    _entries.clear();
    _currentIndex = -1;
  }
}

// ---------------------------------------------------------------------------
// ClipboardService
// ---------------------------------------------------------------------------

/// Service for managing clipboard operations, history, and system clipboard
/// integration.
class ClipboardService {
  /// The clipboard ring buffer.
  final ClipboardRing ring;

  /// How often [watchClipboard] polls the system clipboard (in milliseconds).
  final int pollIntervalMs;

  Timer? _watchTimer;
  String? _lastSystemContent;
  StreamController<ClipboardEntry>? _watchController;

  ClipboardService({int ringSize = 30, this.pollIntervalMs = 1000})
    : ring = ClipboardRing(maxSize: ringSize);

  // -------------------------------------------------------------------------
  // Core operations
  // -------------------------------------------------------------------------

  /// Copy [text] to both the system clipboard and the internal ring.
  Future<void> copy(
    String text, {
    ClipboardSource source = ClipboardSource.user,
    ClipboardContentType contentType = ClipboardContentType.text,
    String? label,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    final entry = ClipboardEntry(
      content: text,
      timestamp: DateTime.now(),
      source: source,
      contentType: contentType,
      label: label,
    );
    ring.add(entry);
    _lastSystemContent = text;
    _watchController?.add(entry);
  }

  /// Paste the most recent entry from the system clipboard.
  ///
  /// Returns null if the clipboard is empty.
  Future<String?> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  /// Paste a specific entry from the ring by [index] (0 = most recent).
  ///
  /// Also copies it to the system clipboard.
  Future<String?> pasteFromRing(int index) async {
    final entry = ring.entryAt(index);
    if (entry == null) return null;
    await Clipboard.setData(ClipboardData(text: entry.content));
    return entry.content;
  }

  /// Cycle through the ring buffer (like Emacs kill-ring / VS Code
  /// clipboard history). Each call returns the next older entry.
  Future<String?> cyclePaste() async {
    final entry = ring.paste();
    if (entry == null) return null;
    await Clipboard.setData(ClipboardData(text: entry.content));
    return entry.content;
  }

  // -------------------------------------------------------------------------
  // History
  // -------------------------------------------------------------------------

  /// Get all entries in the clipboard history (most recent first).
  List<ClipboardEntry> getHistory() => ring.entries;

  /// Clear the clipboard history. Does not affect the system clipboard.
  void clearHistory() => ring.clear();

  // -------------------------------------------------------------------------
  // Specialised copy operations
  // -------------------------------------------------------------------------

  /// Read the content of [path] and copy it to the clipboard.
  Future<void> copyFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }
    final content = await file.readAsString();
    final fileName = path.split(Platform.pathSeparator).last;
    await copy(
      content,
      source: ClipboardSource.tool,
      contentType: ClipboardContentType.code,
      label: fileName,
    );
  }

  /// Format a diff string and copy it to the clipboard.
  ///
  /// [diff] should be a pre-formatted unified diff string.
  Future<void> copyDiff(String diff) async {
    await copy(
      diff,
      source: ClipboardSource.tool,
      contentType: ClipboardContentType.diff,
      label: 'diff',
    );
  }

  /// Copy tool output to the clipboard, optionally trimming whitespace.
  Future<void> copyToolOutput(String output, {bool trim = true}) async {
    final text = trim ? output.trim() : output;
    await copy(
      text,
      source: ClipboardSource.tool,
      contentType: ClipboardContentType.text,
      label: 'tool output',
    );
  }

  /// Copy a file path to the clipboard.
  Future<void> copyPath(String path) async {
    await copy(
      path,
      source: ClipboardSource.user,
      contentType: ClipboardContentType.path,
      label: 'path',
    );
  }

  // -------------------------------------------------------------------------
  // System clipboard monitoring
  // -------------------------------------------------------------------------

  /// Watch the system clipboard for changes.
  ///
  /// Returns a broadcast [Stream] that emits a [ClipboardEntry] whenever
  /// the system clipboard content changes. Polling is used under the hood
  /// since there is no native clipboard-change notification API.
  Stream<ClipboardEntry> watchClipboard() {
    _watchController ??= StreamController<ClipboardEntry>.broadcast(
      onListen: _startPolling,
      onCancel: _stopPolling,
    );
    return _watchController!.stream;
  }

  /// Stop watching the system clipboard and release resources.
  void dispose() {
    _stopPolling();
    _watchController?.close();
    _watchController = null;
  }

  // -------------------------------------------------------------------------
  // Formatting
  // -------------------------------------------------------------------------

  /// Format a [ClipboardEntry] for pasting into a document.
  ///
  /// When [asMarkdown] is true, code and diff entries are wrapped in
  /// fenced code blocks.
  String formatForPaste(ClipboardEntry entry, {bool asMarkdown = false}) {
    if (!asMarkdown) return entry.content;

    switch (entry.contentType) {
      case ClipboardContentType.code:
        return '```\n${entry.content}\n```';
      case ClipboardContentType.diff:
        return '```diff\n${entry.content}\n```';
      case ClipboardContentType.path:
        return '`${entry.content}`';
      case ClipboardContentType.text:
        return entry.content;
    }
  }

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  void _startPolling() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(
      Duration(milliseconds: pollIntervalMs),
      (_) => _pollClipboard(),
    );
  }

  void _stopPolling() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  Future<void> _pollClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text != null && text.isNotEmpty && text != _lastSystemContent) {
        _lastSystemContent = text;
        final entry = ClipboardEntry(
          content: text,
          timestamp: DateTime.now(),
          source: ClipboardSource.system,
          contentType: _inferContentType(text),
        );
        ring.add(entry);
        _watchController?.add(entry);
      }
    } catch (_) {
      // Clipboard access can fail on some platforms; silently ignore.
    }
  }

  /// Heuristically determine the content type of clipboard text.
  ClipboardContentType _inferContentType(String text) {
    // Check if it looks like a file path.
    if (!text.contains('\n') &&
        (text.startsWith('/') || text.startsWith('~'))) {
      return ClipboardContentType.path;
    }
    // Check if it looks like a diff.
    if (text.startsWith('--- ') ||
        text.startsWith('diff --git') ||
        text.startsWith('@@ ')) {
      return ClipboardContentType.diff;
    }
    // Check if it looks like code (contains common code patterns).
    if (text.contains('import ') ||
        text.contains('class ') ||
        text.contains('function ') ||
        text.contains('def ') ||
        text.contains('fn ')) {
      return ClipboardContentType.code;
    }
    return ClipboardContentType.text;
  }
}
