// CommandPalette — port of neomage/src/components/CommandPalette/.
// Quick command search, file finder, symbol navigation overlay.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Types ───

/// Type of palette entry.
enum PaletteEntryType {
  command,
  file,
  symbol,
  recentFile,
  recentCommand,
  action,
  model,
  setting,
}

/// Single entry in the command palette.
class PaletteEntry {
  final String id;
  final String label;
  final String? description;
  final String? detail;
  final PaletteEntryType type;
  final IconData? icon;
  final String? shortcut;
  final int priority;
  final VoidCallback? action;

  const PaletteEntry({
    required this.id,
    required this.label,
    this.description,
    this.detail,
    required this.type,
    this.icon,
    this.shortcut,
    this.priority = 0,
    this.action,
  });
}

/// Palette mode determines what kind of entries to show.
enum PaletteMode {
  commands, // / prefix — slash commands
  files, // no prefix — file search
  symbols, // @ prefix — symbol search
  actions, // > prefix — actions
}

/// Provider of palette entries.
typedef PaletteProvider =
    Future<List<PaletteEntry>> Function(String query, PaletteMode mode);

// ─── CommandPalette widget ───

/// Full-screen command palette overlay (Ctrl+K).
class CommandPalette extends StatefulWidget {
  final PaletteProvider provider;
  final VoidCallback onDismiss;
  final List<PaletteEntry> recentEntries;

  const CommandPalette({
    super.key,
    required this.provider,
    required this.onDismiss,
    this.recentEntries = const [],
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<PaletteEntry> _entries = [];
  int _selectedIndex = 0;
  bool _loading = false;
  PaletteMode _mode = PaletteMode.commands;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    _entries = List.from(widget.recentEntries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  PaletteMode _detectMode(String query) {
    if (query.startsWith('/')) return PaletteMode.commands;
    if (query.startsWith('@')) return PaletteMode.symbols;
    if (query.startsWith('>')) return PaletteMode.actions;
    return PaletteMode.files;
  }

  String _stripPrefix(String query) {
    if (query.startsWith('/') ||
        query.startsWith('@') ||
        query.startsWith('>')) {
      return query.substring(1);
    }
    return query;
  }

  void _onQueryChanged() {
    final query = _controller.text;
    _mode = _detectMode(query);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      _search(_stripPrefix(query));
    });
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() => _loading = true);

    final results = await widget.provider(query, _mode);
    if (!mounted) return;

    // Fuzzy filter + sort
    final filtered =
        query.isEmpty
              ? results
              : results.where((e) => _fuzzyMatch(e.label, query)).toList()
          ..sort((a, b) {
            final aScore = _fuzzyScore(a.label, query) + a.priority;
            final bScore = _fuzzyScore(b.label, query) + b.priority;
            return bScore.compareTo(aScore);
          });

    setState(() {
      _entries = filtered;
      _selectedIndex = 0;
      _loading = false;
    });
  }

  bool _fuzzyMatch(String text, String query) {
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    var qi = 0;
    for (var i = 0; i < lower.length && qi < q.length; i++) {
      if (lower[i] == q[qi]) qi++;
    }
    return qi == q.length;
  }

  int _fuzzyScore(String text, String query) {
    final lower = text.toLowerCase();
    final q = query.toLowerCase();

    // Exact match bonus
    if (lower == q) return 1000;
    // Starts with bonus
    if (lower.startsWith(q)) return 500;
    // Contains bonus
    if (lower.contains(q)) return 250;
    // Consecutive match bonus
    var consecutive = 0;
    var maxConsecutive = 0;
    var qi = 0;
    for (var i = 0; i < lower.length && qi < q.length; i++) {
      if (lower[i] == q[qi]) {
        consecutive++;
        maxConsecutive = max(maxConsecutive, consecutive);
        qi++;
      } else {
        consecutive = 0;
      }
    }
    return maxConsecutive * 10;
  }

  void _select(PaletteEntry entry) {
    widget.onDismiss();
    entry.action?.call();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % max(1, _entries.length);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            ((_selectedIndex - 1 + max(1, _entries.length)) %
                    max(1, _entries.length))
                as int;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && _entries.isNotEmpty) {
      _select(_entries[_selectedIndex]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  IconData _defaultIcon(PaletteEntryType type) {
    switch (type) {
      case PaletteEntryType.command:
        return Icons.terminal;
      case PaletteEntryType.file:
        return Icons.insert_drive_file_outlined;
      case PaletteEntryType.symbol:
        return Icons.code;
      case PaletteEntryType.recentFile:
        return Icons.history;
      case PaletteEntryType.recentCommand:
        return Icons.replay;
      case PaletteEntryType.action:
        return Icons.flash_on;
      case PaletteEntryType.model:
        return Icons.smart_toy_outlined;
      case PaletteEntryType.setting:
        return Icons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 460),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search input
              Focus(
                onKeyEvent: _handleKey,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: _modeHint,
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                    prefixIcon: Icon(
                      _modeIcon,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),

              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
              ),

              // Results list
              Flexible(
                child: _entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _controller.text.isEmpty
                              ? 'Type to search...'
                              : 'No results found.',
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isSelected = index == _selectedIndex;

                          return InkWell(
                            onTap: () => _select(entry),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              color: isSelected
                                  ? (isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.blue.withValues(alpha: 0.08))
                                  : null,
                              child: Row(
                                children: [
                                  Icon(
                                    entry.icon ?? _defaultIcon(entry.type),
                                    size: 18,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.label,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        if (entry.description != null)
                                          Text(
                                            entry.description!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white38
                                                  : Colors.black38,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (entry.shortcut != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.06,
                                              ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        entry.shortcut!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _footerKey('Enter', 'Select'),
                    const SizedBox(width: 16),
                    _footerKey('↑↓', 'Navigate'),
                    const SizedBox(width: 16),
                    _footerKey('Esc', 'Close'),
                    const Spacer(),
                    Text(
                      '${_entries.length} results',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _modeHint {
    switch (_mode) {
      case PaletteMode.commands:
        return 'Type a command...';
      case PaletteMode.files:
        return 'Search files... (/ commands, @ symbols, > actions)';
      case PaletteMode.symbols:
        return 'Search symbols...';
      case PaletteMode.actions:
        return 'Search actions...';
    }
  }

  IconData get _modeIcon {
    switch (_mode) {
      case PaletteMode.commands:
        return Icons.terminal;
      case PaletteMode.files:
        return Icons.search;
      case PaletteMode.symbols:
        return Icons.code;
      case PaletteMode.actions:
        return Icons.flash_on;
    }
  }

  Widget _footerKey(String key, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.15),
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white30 : Colors.black26,
          ),
        ),
      ],
    );
  }
}
