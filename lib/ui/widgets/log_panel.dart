import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

import '../../utils/constants/neomage_translation_constants.dart';

// ---------------------------------------------------------------------------
// Enums & data models
// ---------------------------------------------------------------------------

/// Severity levels for log entries, ordered from least to most severe.
enum LogLevel {
  trace,
  debug,
  info,
  warn,
  error,
  fatal;

  String get label => name.toUpperCase();

  Color get color {
    switch (this) {
      case LogLevel.trace:
        return Colors.grey;
      case LogLevel.debug:
        return Colors.blue;
      case LogLevel.info:
        return Colors.green;
      case LogLevel.warn:
        return Colors.yellow.shade700;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.fatal:
        return Colors.purple;
    }
  }

  IconData get icon {
    switch (this) {
      case LogLevel.trace:
        return Icons.more_horiz;
      case LogLevel.debug:
        return Icons.bug_report_outlined;
      case LogLevel.info:
        return Icons.info_outline;
      case LogLevel.warn:
        return Icons.warning_amber;
      case LogLevel.error:
        return Icons.error_outline;
      case LogLevel.fatal:
        return Icons.dangerous_outlined;
    }
  }
}

/// A single log entry with all associated metadata.
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.stackTrace,
    Map<String, String>? metadata,
  }) : metadata = metadata ?? const {};

  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;
  final String? stackTrace;
  final Map<String, String> metadata;

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String toExportLine() {
    final meta = metadata.entries.map((e) => '${e.key}=${e.value}').join(', ');
    final metaStr = meta.isEmpty ? '' : ' [$meta]';
    final stStr = stackTrace != null ? '\n$stackTrace' : '';
    return '$formattedTime [${level.label}] ($source) $message$metaStr$stStr';
  }
}

/// Filter configuration for the log panel.
class LogFilter {
  LogFilter({
    Set<LogLevel>? levels,
    Set<String>? sources,
    this.searchPattern,
    this.timeRange,
  }) : levels = levels ?? LogLevel.values.toSet(),
       sources = sources ?? {};

  final Set<LogLevel> levels;
  final Set<String> sources;
  final String? searchPattern;
  final DateTimeRange? timeRange;

  bool matches(LogEntry entry) {
    if (!levels.contains(entry.level)) return false;
    if (sources.isNotEmpty && !sources.contains(entry.source)) return false;
    if (searchPattern != null && searchPattern!.isNotEmpty) {
      try {
        final regex = RegExp(searchPattern!, caseSensitive: false);
        if (!regex.hasMatch(entry.message) && !regex.hasMatch(entry.source)) {
          return false;
        }
      } catch (_) {
        // Treat invalid regex as plain substring search.
        final lowerPat = searchPattern!.toLowerCase();
        if (!entry.message.toLowerCase().contains(lowerPat) &&
            !entry.source.toLowerCase().contains(lowerPat)) {
          return false;
        }
      }
    }
    if (timeRange != null) {
      if (entry.timestamp.isBefore(timeRange!.start) ||
          entry.timestamp.isAfter(timeRange!.end)) {
        return false;
      }
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// LogBuffer – circular buffer with stream support
// ---------------------------------------------------------------------------

/// Circular buffer that retains the last [maxEntries] log entries and exposes
/// a stream for new entries as they arrive.
class LogBuffer {
  LogBuffer({this.maxEntries = 50000});

  final int maxEntries;
  final Queue<LogEntry> _entries = Queue<LogEntry>();
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  List<LogEntry> get entries => _entries.toList(growable: false);
  int get length => _entries.length;

  Stream<LogEntry> get stream => _controller.stream;

  void add(LogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    _controller.add(entry);
  }

  void clear() {
    _entries.clear();
  }

  void dispose() {
    _controller.close();
  }

  String export() {
    return _entries.map((e) => e.toExportLine()).join('\n');
  }
}

// ---------------------------------------------------------------------------
// LogService – singleton access point
// ---------------------------------------------------------------------------

/// Singleton service that manages log collection, buffering, and export.
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  final LogBuffer _buffer = LogBuffer();

  LogBuffer get buffer => _buffer;
  Stream<LogEntry> get logStream => _buffer.stream;
  List<LogEntry> get entries => _buffer.entries;

  void addLog({
    required LogLevel level,
    required String source,
    required String message,
    String? stackTrace,
    Map<String, String>? metadata,
  }) {
    _buffer.add(
      LogEntry(
        timestamp: DateTime.now(),
        level: level,
        source: source,
        message: message,
        stackTrace: stackTrace,
        metadata: metadata,
      ),
    );
  }

  void clearLogs() => _buffer.clear();

  String exportLogs() => _buffer.export();

  Set<String> get knownSources {
    final s = <String>{};
    for (final e in _buffer.entries) {
      s.add(e.source);
    }
    return s;
  }

  Map<LogLevel, int> get countsByLevel {
    final m = <LogLevel, int>{};
    for (final l in LogLevel.values) {
      m[l] = 0;
    }
    for (final e in _buffer.entries) {
      m[e.level] = (m[e.level] ?? 0) + 1;
    }
    return m;
  }

  void dispose() => _buffer.dispose();
}

// ---------------------------------------------------------------------------
// LogPanel widget
// ---------------------------------------------------------------------------

/// Full-featured log viewer panel with filtering, virtual scrolling, tail
/// following, keyboard shortcuts, and expandable entries.
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, this.logService, this.initialFilter});

  /// If null, uses [LogService.instance].
  final LogService? logService;
  final LogFilter? initialFilter;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  late final LogService _service;
  late LogFilter _filter;
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late final FocusNode _panelFocus;
  StreamSubscription<LogEntry>? _subscription;

  List<LogEntry> _filtered = [];
  final Set<int> _expandedIndices = {};
  bool _followTail = true;
  bool _showSearch = false;
  String? _selectedSource;

  // ignore: unused_field
  static const double _itemExtent = 32.0;
  // ignore: unused_field
  static const double _expandedExtra = 200.0;

  @override
  void initState() {
    super.initState();
    _service = widget.logService ?? LogService.instance;
    _filter = widget.initialFilter ?? LogFilter();
    _scrollController = ScrollController();
    _searchController = TextEditingController(
      text: _filter.searchPattern ?? '',
    );
    _panelFocus = FocusNode();

    _scrollController.addListener(_onScroll);
    _refilter();

    _subscription = _service.logStream.listen((_) {
      _refilter();
      if (_followTail) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  // ---- helpers ----

  void _refilter() {
    setState(() {
      _filtered = _service.entries.where((e) => _filter.matches(e)).toList();
    });
  }

  void _scrollToEnd() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 20;
    if (_followTail && !atBottom) {
      setState(() => _followTail = false);
    }
  }

  void _toggleLevel(LogLevel level) {
    final levels = Set<LogLevel>.from(_filter.levels);
    if (levels.contains(level)) {
      levels.remove(level);
    } else {
      levels.add(level);
    }
    _filter = LogFilter(
      levels: levels,
      sources: _filter.sources,
      searchPattern: _filter.searchPattern,
      timeRange: _filter.timeRange,
    );
    _refilter();
  }

  void _onSearchChanged(String value) {
    _filter = LogFilter(
      levels: _filter.levels,
      sources: _filter.sources,
      searchPattern: value.isEmpty ? null : value,
      timeRange: _filter.timeRange,
    );
    _refilter();
  }

  void _clearLogs() {
    _service.clearLogs();
    _expandedIndices.clear();
    _refilter();
  }

  void _exportLogs() {
    final data = _service.exportLogs();
    Clipboard.setData(ClipboardData(text: data));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(NeomageTranslationConstants.logsCopied.tr)));
    }
  }

  void _setSource(String? source) {
    _selectedSource = source;
    final sources = source == null ? <String>{} : {source};
    _filter = LogFilter(
      levels: _filter.levels,
      sources: sources,
      searchPattern: _filter.searchPattern,
      timeRange: _filter.timeRange,
    );
    _refilter();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) {
      setState(() => _showSearch = !_showSearch);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyL) {
      _clearLogs();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _scrollToEnd();
      setState(() => _followTail = true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final counts = _service.countsByLevel;
    final sources = _service.knownSources.toList()..sort();

    return Focus(
      focusNode: _panelFocus,
      onKeyEvent: _handleKey,
      autofocus: true,
      child: Column(
        children: [
          _buildHeader(counts),
          _buildFilterBar(sources),
          if (_showSearch) _buildSearchBar(),
          const Divider(height: 1),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<LogLevel, int> counts) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.grey.shade900,
      child: Row(
        children: [
          const Icon(Icons.terminal, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Text(
            'Logs (${_filtered.length})',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 16),
          // Level counts
          ...LogLevel.values.map((l) {
            final c = counts[l] ?? 0;
            if (c == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _LevelBadge(level: l, count: c),
            );
          }),
          const Spacer(),
          // Follow-tail toggle
          Tooltip(
            message: 'Follow tail',
            child: IconButton(
              icon: Icon(
                _followTail
                    ? Icons.vertical_align_bottom
                    : Icons.vertical_align_bottom_outlined,
                color: _followTail ? Colors.cyanAccent : Colors.white54,
                size: 18,
              ),
              onPressed: () {
                setState(() => _followTail = !_followTail);
                if (_followTail) _scrollToEnd();
              },
              iconSize: 18,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          Tooltip(
            message: 'Clear logs (Ctrl+L)',
            child: IconButton(
              icon: const Icon(
                Icons.delete_sweep,
                color: Colors.white54,
                size: 18,
              ),
              onPressed: _clearLogs,
              iconSize: 18,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          Tooltip(
            message: 'Export logs to clipboard',
            child: IconButton(
              icon: const Icon(Icons.copy_all, color: Colors.white54, size: 18),
              onPressed: _exportLogs,
              iconSize: 18,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<String> sources) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: const Color(0xFF303030),
      child: Row(
        children: [
          // Level toggle chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: LogLevel.values.map((l) {
                  final active = _filter.levels.contains(l);
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FilterChip(
                      label: Text(
                        l.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: active ? Colors.white : Colors.white54,
                        ),
                      ),
                      selected: active,
                      selectedColor: l.color.withValues(alpha: 0.35),
                      backgroundColor: Colors.grey.shade800,
                      checkmarkColor: Colors.white,
                      onSelected: (_) => _toggleLevel(l),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Source dropdown
          if (sources.isNotEmpty)
            SizedBox(
              width: 140,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedSource,
                  hint: const Text(
                    'All sources',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  dropdownColor: Colors.grey.shade800,
                  iconEnabledColor: Colors.white54,
                  isDense: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All sources'),
                    ),
                    ...sources.map(
                      (s) =>
                          DropdownMenuItem<String?>(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: _setSource,
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Search toggle
          Tooltip(
            message: 'Search (Ctrl+F)',
            child: IconButton(
              icon: Icon(
                Icons.search,
                color: _showSearch ? Colors.cyanAccent : Colors.white54,
                size: 18,
              ),
              onPressed: () => setState(() => _showSearch = !_showSearch),
              iconSize: 18,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.grey.shade800,
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                hintText: 'Search (regex supported)...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white54),
            onPressed: () {
              _searchController.clear();
              _onSearchChanged('');
              setState(() => _showSearch = false);
            },
            iconSize: 16,
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    if (_filtered.isEmpty) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(
          child: Text(
            'No log entries',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      color: Colors.grey.shade900,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _filtered.length,
        // Use estimated extent for virtualisation; expanded items are taller.
        itemExtent: null,
        cacheExtent: 500,
        itemBuilder: (context, index) {
          final entry = _filtered[index];
          final expanded = _expandedIndices.contains(index);
          return _LogEntryTile(
            entry: entry,
            expanded: expanded,
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedIndices.remove(index);
                } else {
                  _expandedIndices.add(index);
                }
              });
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting private widgets
// ---------------------------------------------------------------------------

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.count});

  final LogLevel level;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${level.label}: $count',
        style: TextStyle(
          color: level.color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({
    required this.entry,
    required this.expanded,
    required this.onTap,
  });

  final LogEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade800, width: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact summary row
            Row(
              children: [
                Icon(entry.level.icon, size: 14, color: entry.level.color),
                const SizedBox(width: 6),
                Text(
                  entry.formattedTime,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: entry.level.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    entry.level.label,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: entry.level.color,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '[${entry.source}]',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (entry.stackTrace != null || entry.metadata.isNotEmpty)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.white38,
                  ),
              ],
            ),
            // Expanded details
            if (expanded) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Full message
                    const Text(
                      'Message:',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      entry.message,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    // Stack trace
                    if (entry.stackTrace != null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Stack Trace:',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        entry.stackTrace!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                    // Metadata
                    if (entry.metadata.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Metadata:',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ...entry.metadata.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '${e.key}: ${e.value}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
