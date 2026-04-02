// TerminalView — port of openclaude/src/components/Terminal/.
// Terminal output display with ANSI colors, scrollback, copy support.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── ANSI color parsing ───

/// ANSI SGR (Select Graphic Rendition) attributes.
class AnsiStyle {
  final Color? foreground;
  final Color? background;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final bool dim;
  final bool inverse;

  const AnsiStyle({
    this.foreground,
    this.background,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.dim = false,
    this.inverse = false,
  });

  AnsiStyle copyWith({
    Color? foreground,
    Color? background,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    bool? dim,
    bool? inverse,
  }) {
    return AnsiStyle(
      foreground: foreground ?? this.foreground,
      background: background ?? this.background,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      dim: dim ?? this.dim,
      inverse: inverse ?? this.inverse,
    );
  }

  static const reset = AnsiStyle();
}

/// A styled span of text from ANSI parsing.
class StyledSpan {
  final String text;
  final AnsiStyle style;

  const StyledSpan(this.text, this.style);
}

/// Standard ANSI 16 colors.
class AnsiColors {
  static const black = Color(0xFF000000);
  static const red = Color(0xFFCC0000);
  static const green = Color(0xFF00CC00);
  static const yellow = Color(0xFFCCCC00);
  static const blue = Color(0xFF0000CC);
  static const magenta = Color(0xFFCC00CC);
  static const cyan = Color(0xFF00CCCC);
  static const white = Color(0xFFCCCCCC);
  static const brightBlack = Color(0xFF555555);
  static const brightRed = Color(0xFFFF5555);
  static const brightGreen = Color(0xFF55FF55);
  static const brightYellow = Color(0xFFFFFF55);
  static const brightBlue = Color(0xFF5555FF);
  static const brightMagenta = Color(0xFFFF55FF);
  static const brightCyan = Color(0xFF55FFFF);
  static const brightWhite = Color(0xFFFFFFFF);

  static const standard = [
    black, red, green, yellow, blue, magenta, cyan, white,
    brightBlack, brightRed, brightGreen, brightYellow,
    brightBlue, brightMagenta, brightCyan, brightWhite,
  ];

  /// Get color for 256-color palette.
  static Color color256(int index) {
    if (index < 16) return standard[index];
    if (index < 232) {
      // 6x6x6 color cube
      final n = index - 16;
      final b = (n % 6) * 51;
      final g = ((n ~/ 6) % 6) * 51;
      final r = (n ~/ 36) * 51;
      return Color.fromARGB(255, r, g, b);
    }
    // Grayscale ramp
    final v = (index - 232) * 10 + 8;
    return Color.fromARGB(255, v, v, v);
  }
}

/// Parse ANSI escape sequences in text.
List<StyledSpan> parseAnsi(String input) {
  final spans = <StyledSpan>[];
  var style = const AnsiStyle();
  final buffer = StringBuffer();
  var i = 0;

  void flushBuffer() {
    if (buffer.isNotEmpty) {
      spans.add(StyledSpan(buffer.toString(), style));
      buffer.clear();
    }
  }

  while (i < input.length) {
    // Check for ESC[
    if (i + 1 < input.length &&
        input.codeUnitAt(i) == 0x1B &&
        input[i + 1] == '[') {
      flushBuffer();
      i += 2;

      // Parse CSI sequence
      final paramStart = i;
      while (i < input.length &&
          (input.codeUnitAt(i) >= 0x30 && input.codeUnitAt(i) <= 0x3F)) {
        i++;
      }
      // Skip intermediate bytes
      while (i < input.length &&
          (input.codeUnitAt(i) >= 0x20 && input.codeUnitAt(i) <= 0x2F)) {
        i++;
      }
      // Final byte
      if (i < input.length) {
        final finalByte = input[i];
        i++;

        if (finalByte == 'm') {
          // SGR sequence
          final params = input
              .substring(paramStart, i - 1)
              .split(';')
              .map((s) => int.tryParse(s) ?? 0)
              .toList();

          if (params.isEmpty || (params.length == 1 && params[0] == 0)) {
            style = const AnsiStyle();
          } else {
            var j = 0;
            while (j < params.length) {
              final p = params[j];
              switch (p) {
                case 0:
                  style = const AnsiStyle();
                  break;
                case 1:
                  style = style.copyWith(bold: true);
                  break;
                case 2:
                  style = style.copyWith(dim: true);
                  break;
                case 3:
                  style = style.copyWith(italic: true);
                  break;
                case 4:
                  style = style.copyWith(underline: true);
                  break;
                case 7:
                  style = style.copyWith(inverse: true);
                  break;
                case 9:
                  style = style.copyWith(strikethrough: true);
                  break;
                case 22:
                  style = style.copyWith(bold: false, dim: false);
                  break;
                case 23:
                  style = style.copyWith(italic: false);
                  break;
                case 24:
                  style = style.copyWith(underline: false);
                  break;
                case 27:
                  style = style.copyWith(inverse: false);
                  break;
                case 29:
                  style = style.copyWith(strikethrough: false);
                  break;
                case >= 30 && <= 37:
                  style = style.copyWith(
                      foreground: AnsiColors.standard[p - 30]);
                  break;
                case 38:
                  // Extended foreground
                  if (j + 1 < params.length && params[j + 1] == 5 &&
                      j + 2 < params.length) {
                    style = style.copyWith(
                        foreground: AnsiColors.color256(params[j + 2]));
                    j += 2;
                  } else if (j + 1 < params.length &&
                      params[j + 1] == 2 &&
                      j + 4 < params.length) {
                    style = style.copyWith(
                        foreground: Color.fromARGB(
                            255, params[j + 2], params[j + 3], params[j + 4]));
                    j += 4;
                  }
                  break;
                case 39:
                  style = style.copyWith(foreground: null);
                  break;
                case >= 40 && <= 47:
                  style = style.copyWith(
                      background: AnsiColors.standard[p - 40]);
                  break;
                case 48:
                  // Extended background
                  if (j + 1 < params.length && params[j + 1] == 5 &&
                      j + 2 < params.length) {
                    style = style.copyWith(
                        background: AnsiColors.color256(params[j + 2]));
                    j += 2;
                  } else if (j + 1 < params.length &&
                      params[j + 1] == 2 &&
                      j + 4 < params.length) {
                    style = style.copyWith(
                        background: Color.fromARGB(
                            255, params[j + 2], params[j + 3], params[j + 4]));
                    j += 4;
                  }
                  break;
                case 49:
                  style = style.copyWith(background: null);
                  break;
                case >= 90 && <= 97:
                  style = style.copyWith(
                      foreground: AnsiColors.standard[p - 90 + 8]);
                  break;
                case >= 100 && <= 107:
                  style = style.copyWith(
                      background: AnsiColors.standard[p - 100 + 8]);
                  break;
              }
              j++;
            }
          }
        }
        // Ignore other CSI sequences (cursor movement, etc.)
      }
    } else {
      buffer.writeCharCode(input.codeUnitAt(i));
      i++;
    }
  }

  flushBuffer();
  return spans;
}

/// Strip all ANSI escape sequences from text.
String stripAnsi(String input) {
  return input.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
}

// ─── Terminal output line ───

/// A single line in the terminal output.
class TerminalLine {
  final String rawText;
  final List<StyledSpan>? _parsed;
  final TerminalLineType type;
  final DateTime timestamp;

  TerminalLine({
    required this.rawText,
    this.type = TerminalLineType.stdout,
    DateTime? timestamp,
  })  : _parsed = null,
        timestamp = timestamp ?? DateTime.now();

  List<StyledSpan> get spans => _parsed ?? parseAnsi(rawText);

  String get plainText => stripAnsi(rawText);
}

enum TerminalLineType { stdout, stderr, system, command, separator }

// ─── TerminalView widget ───

/// Terminal output viewer with ANSI color support and scrollback.
class TerminalView extends StatefulWidget {
  final List<TerminalLine> lines;
  final bool autoScroll;
  final int maxScrollback;
  final bool showTimestamps;
  final bool showLineNumbers;
  final TextStyle? baseStyle;
  final Color? backgroundColor;
  final ScrollController? scrollController;

  const TerminalView({
    super.key,
    required this.lines,
    this.autoScroll = true,
    this.maxScrollback = 10000,
    this.showTimestamps = false,
    this.showLineNumbers = false,
    this.baseStyle,
    this.backgroundColor,
    this.scrollController,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  late final ScrollController _scrollController;
  bool _userScrolled = false;
  String? _searchQuery;
  List<int> _searchMatches = [];
  int _currentMatch = -1;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(TerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoScroll &&
        !_userScrolled &&
        widget.lines.length > oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    _userScrolled = (maxScroll - currentScroll) > 50;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
      _userScrolled = false;
    }
  }

  void _search(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchQuery = null;
        _searchMatches = [];
        _currentMatch = -1;
      });
      return;
    }

    final matches = <int>[];
    final lower = query.toLowerCase();
    for (var i = 0; i < widget.lines.length; i++) {
      if (widget.lines[i].plainText.toLowerCase().contains(lower)) {
        matches.add(i);
      }
    }

    setState(() {
      _searchQuery = query;
      _searchMatches = matches;
      _currentMatch = matches.isNotEmpty ? 0 : -1;
    });
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentMatch = (_currentMatch + 1) % _searchMatches.length;
    });
  }

  void _prevMatch() {
    if (_searchMatches.isEmpty) return;
    setState(() {
      _currentMatch = (_currentMatch - 1 + _searchMatches.length) %
          _searchMatches.length;
    });
  }

  void _copyAll() {
    final text =
        widget.lines.map((l) => l.plainText).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Color _lineTypeColor(TerminalLineType type, bool isDark) {
    switch (type) {
      case TerminalLineType.stdout:
        return isDark ? Colors.white : Colors.black87;
      case TerminalLineType.stderr:
        return Colors.red.shade300;
      case TerminalLineType.system:
        return isDark ? Colors.blue.shade300 : Colors.blue.shade700;
      case TerminalLineType.command:
        return isDark ? Colors.green.shade300 : Colors.green.shade700;
      case TerminalLineType.separator:
        return isDark ? Colors.white24 : Colors.black26;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = widget.backgroundColor ??
        (isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF8F8FB));

    final baseStyle = widget.baseStyle ??
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
          color: isDark ? Colors.white : Colors.black87,
        );

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF141428)
                : const Color(0xFFF0F0F5),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Row(
            children: [
              // Search
              SizedBox(
                width: 200,
                height: 28,
                child: TextField(
                  onChanged: _search,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search output...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                    prefixIcon:
                        Icon(Icons.search, size: 14, color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),

              if (_searchMatches.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${_currentMatch + 1}/${_searchMatches.length}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                IconButton(
                  onPressed: _prevMatch,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 16),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
                IconButton(
                  onPressed: _nextMatch,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],

              const Spacer(),

              // Line count
              Text(
                '${widget.lines.length} lines',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
              ),
              const SizedBox(width: 8),

              // Copy all
              IconButton(
                onPressed: _copyAll,
                icon: const Icon(Icons.copy, size: 14),
                tooltip: 'Copy all',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),

              // Scroll to bottom
              IconButton(
                onPressed: _scrollToBottom,
                icon: const Icon(Icons.arrow_downward, size: 14),
                tooltip: 'Scroll to bottom',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),

        // Terminal content
        Expanded(
          child: Container(
            color: bgColor,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = widget.lines[index];
                final isMatch = _searchQuery != null &&
                    _searchMatches.contains(index);
                final isCurrentMatch =
                    _currentMatch >= 0 &&
                    _currentMatch < _searchMatches.length &&
                    _searchMatches[_currentMatch] == index;

                return Container(
                  color: isCurrentMatch
                      ? Colors.yellow.withValues(alpha: 0.2)
                      : isMatch
                          ? Colors.yellow.withValues(alpha: 0.08)
                          : null,
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line number
                      if (widget.showLineNumbers)
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${index + 1}',
                            style: baseStyle.copyWith(
                              color: isDark
                                  ? Colors.white24
                                  : Colors.black12,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      if (widget.showLineNumbers)
                        const SizedBox(width: 8),

                      // Timestamp
                      if (widget.showTimestamps)
                        Text(
                          '${line.timestamp.hour.toString().padLeft(2, '0')}:'
                          '${line.timestamp.minute.toString().padLeft(2, '0')}:'
                          '${line.timestamp.second.toString().padLeft(2, '0')} ',
                          style: baseStyle.copyWith(
                            color: isDark
                                ? Colors.white24
                                : Colors.black12,
                            fontSize: 11,
                          ),
                        ),

                      // Content
                      Expanded(
                        child: _buildStyledLine(
                            line, baseStyle, isDark),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Scroll indicator
        if (_userScrolled)
          GestureDetector(
            onTap: _scrollToBottom,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: isDark
                  ? Colors.blue.shade900.withValues(alpha: 0.8)
                  : Colors.blue.shade50,
              child: Text(
                '↓ New output below — click to scroll',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Colors.blue.shade300
                      : Colors.blue.shade700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStyledLine(
      TerminalLine line, TextStyle baseStyle, bool isDark) {
    if (line.type == TerminalLineType.separator) {
      return Divider(
        height: 1,
        color: isDark ? Colors.white12 : Colors.black12,
      );
    }

    final spans = line.spans;
    if (spans.length == 1 && spans[0].style == const AnsiStyle()) {
      // Simple unstyled text
      return Text(
        spans[0].text,
        style: baseStyle.copyWith(
          color: _lineTypeColor(line.type, isDark),
        ),
      );
    }

    // Styled text with ANSI colors
    return RichText(
      text: TextSpan(
        children: spans.map((span) {
          var fg = span.style.foreground ??
              _lineTypeColor(line.type, isDark);
          var bg = span.style.background;

          if (span.style.inverse) {
            final tmp = fg;
            fg = bg ?? (isDark ? Colors.white : Colors.black);
            bg = tmp;
          }

          if (span.style.dim) {
            fg = fg.withValues(alpha: 0.5);
          }

          return TextSpan(
            text: span.text,
            style: baseStyle.copyWith(
              color: fg,
              backgroundColor: bg,
              fontWeight:
                  span.style.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle:
                  span.style.italic ? FontStyle.italic : FontStyle.normal,
              decoration: TextDecoration.combine([
                if (span.style.underline) TextDecoration.underline,
                if (span.style.strikethrough)
                  TextDecoration.lineThrough,
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Terminal buffer ───

/// Manages terminal output buffer with scrollback limit.
class TerminalBuffer {
  final int maxLines;
  final List<TerminalLine> _lines = [];
  final StreamController<TerminalLine> _lineAdded =
      StreamController.broadcast();

  TerminalBuffer({this.maxLines = 10000});

  List<TerminalLine> get lines => List.unmodifiable(_lines);
  Stream<TerminalLine> get onLineAdded => _lineAdded.stream;
  int get length => _lines.length;

  void addLine(String text,
      {TerminalLineType type = TerminalLineType.stdout}) {
    final line = TerminalLine(rawText: text, type: type);
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeAt(0);
    }
    _lineAdded.add(line);
  }

  void addLines(String text,
      {TerminalLineType type = TerminalLineType.stdout}) {
    for (final line in text.split('\n')) {
      addLine(line, type: type);
    }
  }

  void addCommand(String command) {
    addLine('\$ $command', type: TerminalLineType.command);
  }

  void addSystem(String message) {
    addLine(message, type: TerminalLineType.system);
  }

  void addSeparator() {
    _lines.add(TerminalLine(
      rawText: '',
      type: TerminalLineType.separator,
    ));
  }

  void clear() {
    _lines.clear();
  }

  String toPlainText() {
    return _lines.map((l) => l.plainText).join('\n');
  }

  void dispose() {
    _lineAdded.close();
  }
}
