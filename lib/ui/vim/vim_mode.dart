// vim_mode.dart — Vim emulation layer for flutter_claw
// Port of neom_claw/src/vim/ (~1.5K TS LOC) to pure Dart + minimal Flutter.

import 'dart:math';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum VimMode {
  normal,
  insert,
  visual,
  visualLine,
  command,
  replace;

  String get label => switch (this) {
    normal => 'NORMAL',
    insert => 'INSERT',
    visual => 'VISUAL',
    visualLine => 'V-LINE',
    command => 'COMMAND',
    replace => 'REPLACE',
  };
}

enum VimOperator {
  delete,
  change,
  yank,
  indent,
  unindent,
  format;

  String get char => switch (this) {
    delete => 'd',
    change => 'c',
    yank => 'y',
    indent => '>',
    unindent => '<',
    format => 'gq',
  };

  static VimOperator? fromChar(String ch) => switch (ch) {
    'd' => delete,
    'c' => change,
    'y' => yank,
    '>' => indent,
    '<' => unindent,
    _ => null,
  };
}

// ---------------------------------------------------------------------------
// VimMotion — sealed hierarchy for movement types
// ---------------------------------------------------------------------------

sealed class VimMotion {
  const VimMotion();
}

class CharMotion extends VimMotion {
  final int delta; // +1 right, -1 left
  const CharMotion(this.delta);
}

class WordMotion extends VimMotion {
  final bool forward;
  final bool end; // true for 'e'
  const WordMotion({required this.forward, this.end = false});
}

class LineMotion extends VimMotion {
  final int delta; // +n down, -n up
  const LineMotion(this.delta);
}

class LinePositionMotion extends VimMotion {
  final LinePosition position;
  const LinePositionMotion(this.position);
}

enum LinePosition { start, firstNonBlank, end }

class ParagraphMotion extends VimMotion {
  final bool forward;
  const ParagraphMotion({required this.forward});
}

class SearchMotion extends VimMotion {
  final String pattern;
  final bool forward;
  const SearchMotion({required this.pattern, required this.forward});
}

class FindCharMotion extends VimMotion {
  final String char;
  final bool forward;
  final bool before; // t/T vs f/F
  const FindCharMotion({
    required this.char,
    required this.forward,
    this.before = false,
  });
}

class MatchBracketMotion extends VimMotion {
  const MatchBracketMotion();
}

class EntireLineMotion extends VimMotion {
  const EntireLineMotion();
}

class ToLineMotion extends VimMotion {
  final int line; // 0-based
  const ToLineMotion(this.line);
}

class FirstLineMotion extends VimMotion {
  const FirstLineMotion();
}

class LastLineMotion extends VimMotion {
  const LastLineMotion();
}

// ---------------------------------------------------------------------------
// VimRegister — clipboard registers
// ---------------------------------------------------------------------------

class VimRegister {
  final Map<String, String> _registers = {};
  String _lastYank = '';

  static const String unnamed = '"';
  static const String smallDelete = '-';
  static const String systemClipboard = '+';
  static const String selection = '*';
  static const String lastInserted = '.';
  static const String lastCommand = ':';
  static const String currentFile = '%';
  static const String alternateFile = '#';
  static const String searchPattern = '/';

  void set(String name, String content) {
    if (name.length != 1) return;
    _registers[name] = content;
    if (name == unnamed) {
      // Also populate register 0 for yanks handled externally
    }
  }

  String get(String name) => _registers[name] ?? '';

  void yank(String content) {
    _lastYank = content;
    _registers['0'] = content;
    _registers[unnamed] = content;
  }

  void delete(String content) {
    // Shift numbered registers 1-9
    for (int i = 9; i > 1; i--) {
      final prev = _registers['${i - 1}'];
      if (prev != null) _registers['$i'] = prev;
    }
    _registers['1'] = content;
    _registers[unnamed] = content;
  }

  String paste(String? registerName) {
    final name = registerName ?? unnamed;
    return _registers[name] ?? '';
  }

  void clear() {
    _registers.clear();
    _lastYank = '';
  }

  String get lastYank => _lastYank;

  Map<String, String> get all => Map.unmodifiable(_registers);
}

// ---------------------------------------------------------------------------
// CursorPosition
// ---------------------------------------------------------------------------

class CursorPosition {
  final int line;
  final int column;

  const CursorPosition(this.line, this.column);

  CursorPosition copyWith({int? line, int? column}) =>
      CursorPosition(line ?? this.line, column ?? this.column);

  @override
  bool operator ==(Object other) =>
      other is CursorPosition && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => 'Cursor($line, $column)';
}

// ---------------------------------------------------------------------------
// VimState — mutable state for the vim emulation
// ---------------------------------------------------------------------------

class VimState {
  VimMode mode;
  CursorPosition cursor;
  CursorPosition? visualAnchor;
  int count;
  VimOperator? pendingOperator;
  String? pendingRegister;
  final VimRegister register;
  String lastSearch;
  bool lastSearchForward;
  String lastChange;
  String commandBuffer;
  bool replaceMode;

  // Undo/redo
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  int _undoGroupCounter = 0;

  VimState()
    : mode = VimMode.normal,
      cursor = const CursorPosition(0, 0),
      count = 0,
      register = VimRegister(),
      lastSearch = '',
      lastSearchForward = true,
      lastChange = '',
      commandBuffer = '',
      replaceMode = false;

  int get effectiveCount => count == 0 ? 1 : count;

  void resetPartial() {
    count = 0;
    pendingOperator = null;
    pendingRegister = null;
  }

  void pushUndo(List<String> lines, CursorPosition pos) {
    _undoStack.add(
      _UndoEntry(lines: List.of(lines), cursor: pos, group: _undoGroupCounter),
    );
    _redoStack.clear();
  }

  void beginUndoGroup() => _undoGroupCounter++;

  // ignore: library_private_types_in_public_api
  _UndoEntry? popUndo() => _undoStack.isEmpty ? null : _undoStack.removeLast();
  // ignore: library_private_types_in_public_api
  _UndoEntry? popRedo() => _redoStack.isEmpty ? null : _redoStack.removeLast();

  void pushRedo(List<String> lines, CursorPosition pos) {
    _redoStack.add(
      _UndoEntry(lines: List.of(lines), cursor: pos, group: _undoGroupCounter),
    );
  }
}

class _UndoEntry {
  final List<String> lines;
  final CursorPosition cursor;
  final int group;
  const _UndoEntry({
    required this.lines,
    required this.cursor,
    required this.group,
  });
}

// ---------------------------------------------------------------------------
// VimStatusLine
// ---------------------------------------------------------------------------

class VimStatusLine {
  final VimState state;
  final String fileName;
  final int totalLines;
  final bool modified;

  const VimStatusLine({
    required this.state,
    this.fileName = '[No Name]',
    this.totalLines = 0,
    this.modified = false,
  });

  String format() {
    final modMark = modified ? ' [+]' : '';
    final modeLabel = state.mode.label;
    final line = state.cursor.line + 1;
    final col = state.cursor.column + 1;
    final pct = totalLines == 0
        ? 'Top'
        : '${(line * 100 ~/ totalLines).clamp(0, 100)}%';

    final left = '-- $modeLabel -- $fileName$modMark';
    final right = '$line,$col   $pct';

    if (state.mode == VimMode.command) {
      return ':${state.commandBuffer}';
    }
    return '$left${' ' * max(0, 60 - left.length - right.length)}$right';
  }
}

// ---------------------------------------------------------------------------
// VimCommand — ex command parsing and execution
// ---------------------------------------------------------------------------

class VimCommandResult {
  final bool success;
  final String message;
  final bool shouldQuit;
  final bool shouldSave;

  const VimCommandResult({
    this.success = true,
    this.message = '',
    this.shouldQuit = false,
    this.shouldSave = false,
  });
}

sealed class VimCommand {
  const VimCommand();
}

class WriteCommand extends VimCommand {
  final String? fileName;
  const WriteCommand({this.fileName});
}

class QuitCommand extends VimCommand {
  final bool force;
  const QuitCommand({this.force = false});
}

class WriteQuitCommand extends VimCommand {
  const WriteQuitCommand();
}

class SubstituteCommand extends VimCommand {
  final String pattern;
  final String replacement;
  final bool global;
  final bool confirmEach;
  const SubstituteCommand({
    required this.pattern,
    required this.replacement,
    this.global = false,
    this.confirmEach = false,
  });
}

class SetCommand extends VimCommand {
  final String option;
  final String? value;
  const SetCommand({required this.option, this.value});
}

class ShellCommand extends VimCommand {
  final String command;
  const ShellCommand({required this.command});
}

class GotoLineCommand extends VimCommand {
  final int line;
  const GotoLineCommand({required this.line});
}

class NoOpCommand extends VimCommand {
  final String raw;
  const NoOpCommand({required this.raw});
}

VimCommand parseVimCommand(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const NoOpCommand(raw: '');

  // :w [file]
  if (trimmed == 'w' || trimmed.startsWith('w ')) {
    final file = trimmed.length > 2 ? trimmed.substring(2).trim() : null;
    return WriteCommand(fileName: file);
  }

  // :q / :q!
  if (trimmed == 'q') return const QuitCommand();
  if (trimmed == 'q!') return const QuitCommand(force: true);

  // :wq / :x
  if (trimmed == 'wq' || trimmed == 'x') return const WriteQuitCommand();

  // :s/old/new/[g][c]
  final subMatch = RegExp(r'^s/([^/]*)/([^/]*)/?([gc]*)$').firstMatch(trimmed);
  if (subMatch != null) {
    final flags = subMatch.group(3) ?? '';
    return SubstituteCommand(
      pattern: subMatch.group(1)!,
      replacement: subMatch.group(2)!,
      global: flags.contains('g'),
      confirmEach: flags.contains('c'),
    );
  }

  // :set option[=value]
  if (trimmed.startsWith('set ')) {
    final rest = trimmed.substring(4).trim();
    final eqIdx = rest.indexOf('=');
    if (eqIdx >= 0) {
      return SetCommand(
        option: rest.substring(0, eqIdx).trim(),
        value: rest.substring(eqIdx + 1).trim(),
      );
    }
    return SetCommand(option: rest);
  }

  // :! shell command
  if (trimmed.startsWith('!')) {
    return ShellCommand(command: trimmed.substring(1).trim());
  }

  // :<number> goto line
  final lineNum = int.tryParse(trimmed);
  if (lineNum != null) {
    return GotoLineCommand(line: lineNum);
  }

  return NoOpCommand(raw: trimmed);
}

// ---------------------------------------------------------------------------
// VimKeyHandler — process keystrokes
// ---------------------------------------------------------------------------

typedef BufferModifier = void Function(List<String> lines);

class VimKeyHandler {
  final VimState state;
  List<String> _lines;
  bool _modified = false;
  final void Function(String)? onStatusMessage;
  String _pendingKeys = '';

  VimKeyHandler({
    required this.state,
    required List<String> lines,
    this.onStatusMessage,
  }) : _lines = lines;

  // ignore: unnecessary_getters_setters
  List<String> get lines => _lines;
  bool get modified => _modified;
  // ignore: unnecessary_getters_setters
  set lines(List<String> value) => _lines = value;

  /// Main entry point — returns true if the key was consumed.
  bool handleKey(String key) {
    switch (state.mode) {
      case VimMode.normal:
        return _handleNormal(key);
      case VimMode.insert:
        return _handleInsert(key);
      case VimMode.visual:
      case VimMode.visualLine:
        return _handleVisual(key);
      case VimMode.command:
        return _handleCommand(key);
      case VimMode.replace:
        return _handleReplace(key);
    }
  }

  // -- Normal mode ----------------------------------------------------------

  bool _handleNormal(String key) {
    // Accumulate count prefix
    if (state.pendingOperator == null &&
        state.count >= 0 &&
        key.length == 1 &&
        '123456789'.contains(key)) {
      state.count = state.count * 10 + int.parse(key);
      return true;
    }
    if (state.count > 0 && key == '0') {
      state.count = state.count * 10;
      return true;
    }

    // Register prefix
    if (key == '"') {
      _pendingKeys = '"';
      return true;
    }
    if (_pendingKeys == '"' && key.length == 1) {
      state.pendingRegister = key;
      _pendingKeys = '';
      return true;
    }

    // Operator pending
    final op = VimOperator.fromChar(key);
    if (op != null && state.pendingOperator == null) {
      state.pendingOperator = op;
      return true;
    }

    // Double-operator (dd, yy, cc, >>, <<)
    if (state.pendingOperator != null &&
        VimOperator.fromChar(key) == state.pendingOperator) {
      _applyOperatorOnLines(state.pendingOperator!, state.effectiveCount);
      state.resetPartial();
      return true;
    }

    // Motion keys
    final motion = _parseMotion(key);
    if (motion != null) {
      if (state.pendingOperator != null) {
        _applyOperatorWithMotion(
          state.pendingOperator!,
          motion,
          state.effectiveCount,
        );
        state.resetPartial();
      } else {
        _moveCursor(motion, state.effectiveCount);
        state.resetPartial();
      }
      return true;
    }

    // Mode switches
    switch (key) {
      case 'i':
        _enterInsert();
        return true;
      case 'a':
        state.cursor = state.cursor.copyWith(
          column: min(state.cursor.column + 1, _currentLineLength()),
        );
        _enterInsert();
        return true;
      case 'o':
        _openLineBelow();
        return true;
      case 'O':
        _openLineAbove();
        return true;
      case 'v':
        state.mode = VimMode.visual;
        state.visualAnchor = state.cursor;
        state.resetPartial();
        return true;
      case 'V':
        state.mode = VimMode.visualLine;
        state.visualAnchor = state.cursor;
        state.resetPartial();
        return true;
      case ':':
        state.mode = VimMode.command;
        state.commandBuffer = '';
        state.resetPartial();
        return true;
      case 'R':
        state.mode = VimMode.replace;
        state.resetPartial();
        return true;

      // Single-key actions
      case 'x':
        _deleteChars(state.effectiveCount);
        state.resetPartial();
        return true;
      case 'p':
        _paste(after: true);
        state.resetPartial();
        return true;
      case 'P':
        _paste(after: false);
        state.resetPartial();
        return true;
      case 'u':
        _undo();
        state.resetPartial();
        return true;
      case 'r':
        _pendingKeys = 'r';
        return true;
      case '.':
        _repeatLastChange();
        return true;
      case '/':
        state.mode = VimMode.command;
        state.commandBuffer = '/';
        return true;
      case '?':
        state.mode = VimMode.command;
        state.commandBuffer = '?';
        return true;
      case 'n':
        _searchNext(forward: true);
        state.resetPartial();
        return true;
      case 'N':
        _searchNext(forward: false);
        state.resetPartial();
        return true;
      case 'J':
        _joinLines(state.effectiveCount);
        state.resetPartial();
        return true;
      case '~':
        _toggleCase();
        state.resetPartial();
        return true;
    }

    // Replace single char (after 'r' pending)
    if (_pendingKeys == 'r' && key.length == 1) {
      _replaceChar(key);
      _pendingKeys = '';
      state.resetPartial();
      return true;
    }

    // g-prefix motions
    if (_pendingKeys == '' && key == 'g') {
      _pendingKeys = 'g';
      return true;
    }
    if (_pendingKeys == 'g') {
      _pendingKeys = '';
      switch (key) {
        case 'g':
          if (state.pendingOperator != null) {
            _applyOperatorWithMotion(
              state.pendingOperator!,
              const FirstLineMotion(),
              1,
            );
            state.resetPartial();
          } else {
            final targetLine = state.count > 0 ? state.count - 1 : 0;
            _moveCursor(ToLineMotion(targetLine), 1);
            state.resetPartial();
          }
          return true;
        case 'q':
          state.pendingOperator ??= VimOperator.format;
          return true;
      }
      return false;
    }

    state.resetPartial();
    return false;
  }

  VimMotion? _parseMotion(String key) => switch (key) {
    'h' => const CharMotion(-1),
    'l' => const CharMotion(1),
    'j' => const LineMotion(1),
    'k' => const LineMotion(-1),
    'w' => const WordMotion(forward: true),
    'b' => const WordMotion(forward: false),
    'e' => const WordMotion(forward: true, end: true),
    '0' => const LinePositionMotion(LinePosition.start),
    '\$' => const LinePositionMotion(LinePosition.end),
    '^' => const LinePositionMotion(LinePosition.firstNonBlank),
    '{' => const ParagraphMotion(forward: false),
    '}' => const ParagraphMotion(forward: true),
    'G' => const LastLineMotion(),
    '%' => const MatchBracketMotion(),
    _ => null,
  };

  // -- Cursor movement ------------------------------------------------------

  void _moveCursor(VimMotion motion, int count) {
    switch (motion) {
      case CharMotion m:
        final newCol = (state.cursor.column + m.delta * count).clamp(
          0,
          max(0, _currentLineLength() - 1),
        );
        state.cursor = state.cursor.copyWith(column: newCol.toInt());
      case LineMotion m:
        final newLine = (state.cursor.line + m.delta * count).clamp(
          0,
          _lines.length - 1,
        );
        final maxCol = max(0, _lineLength(newLine) - 1);
        state.cursor = CursorPosition(
          newLine,
          min(state.cursor.column, maxCol),
        );
      case WordMotion m:
        for (int i = 0; i < count; i++) {
          _moveWord(forward: m.forward, toEnd: m.end);
        }
      case LinePositionMotion m:
        switch (m.position) {
          case LinePosition.start:
            state.cursor = state.cursor.copyWith(column: 0);
          case LinePosition.end:
            state.cursor = state.cursor.copyWith(
              column: max(0, _currentLineLength() - 1),
            );
          case LinePosition.firstNonBlank:
            final line = _currentLine();
            final idx = line.indexOf(RegExp(r'\S'));
            state.cursor = state.cursor.copyWith(column: idx < 0 ? 0 : idx);
        }
      case ParagraphMotion m:
        _moveParagraph(m.forward, count);
      case SearchMotion m:
        _performSearch(m.pattern, m.forward);
      case FindCharMotion m:
        _findChar(m.char, m.forward, m.before, count);
      case MatchBracketMotion _:
        _matchBracket();
      case EntireLineMotion _:
        break; // handled by operator
      case ToLineMotion m:
        final target = m.line.clamp(0, _lines.length - 1);
        state.cursor = CursorPosition(target, 0);
        _moveToFirstNonBlank();
      case FirstLineMotion _:
        state.cursor = const CursorPosition(0, 0);
        _moveToFirstNonBlank();
      case LastLineMotion _:
        state.cursor = CursorPosition(_lines.length - 1, 0);
        _moveToFirstNonBlank();
    }
  }

  void _moveWord({required bool forward, required bool toEnd}) {
    final wordRe = RegExp(r'[a-zA-Z0-9_]+|[^\s\w]+');
    int line = state.cursor.line;
    int col = state.cursor.column;

    if (forward) {
      final text = _lines[line];
      final matches = wordRe.allMatches(text).toList();
      for (final m in matches) {
        final target = toEnd ? m.end - 1 : m.start;
        if (target > col) {
          state.cursor = CursorPosition(line, target);
          return;
        }
      }
      // Move to next line
      if (line + 1 < _lines.length) {
        state.cursor = CursorPosition(line + 1, 0);
        if (!toEnd) _moveToFirstNonBlank();
      }
    } else {
      if (col == 0 && line > 0) {
        line--;
        col = _lineLength(line);
      }
      final text = _lines[line];
      final matches = wordRe.allMatches(text).toList().reversed;
      for (final m in matches) {
        if (m.start < col) {
          state.cursor = CursorPosition(line, m.start);
          return;
        }
      }
      state.cursor = CursorPosition(line, 0);
    }
  }

  void _moveParagraph(bool forward, int count) {
    int line = state.cursor.line;
    for (int i = 0; i < count; i++) {
      if (forward) {
        line++;
        while (line < _lines.length && _lines[line].trim().isNotEmpty) {
          line++;
        }
        while (line < _lines.length && _lines[line].trim().isEmpty) {
          line++;
        }
        line = min(line, _lines.length - 1);
      } else {
        line--;
        while (line > 0 && _lines[line].trim().isEmpty) {
          line--;
        }
        while (line > 0 && _lines[line].trim().isNotEmpty) {
          line--;
        }
        line = max(line, 0);
      }
    }
    state.cursor = CursorPosition(line, 0);
  }

  void _moveToFirstNonBlank() {
    final line = _currentLine();
    final idx = line.indexOf(RegExp(r'\S'));
    state.cursor = state.cursor.copyWith(column: idx < 0 ? 0 : idx);
  }

  // -- Operators ------------------------------------------------------------

  void _applyOperatorOnLines(VimOperator op, int count) {
    state.beginUndoGroup();
    state.pushUndo(_lines, state.cursor);
    final startLine = state.cursor.line;
    final endLine = min(startLine + count, _lines.length);
    final removed = _lines.sublist(startLine, endLine);
    final text = removed.join('\n');

    switch (op) {
      case VimOperator.delete:
        state.register.delete(text);
        _lines.removeRange(startLine, endLine);
        if (_lines.isEmpty) _lines.add('');
        state.cursor = CursorPosition(min(startLine, _lines.length - 1), 0);
        _moveToFirstNonBlank();
        _modified = true;
      case VimOperator.change:
        state.register.delete(text);
        _lines.removeRange(startLine, endLine);
        _lines.insert(startLine, '');
        state.cursor = CursorPosition(startLine, 0);
        _enterInsert();
        _modified = true;
      case VimOperator.yank:
        state.register.yank(text);
        onStatusMessage?.call('${removed.length} lines yanked');
      case VimOperator.indent:
        for (int i = startLine; i < endLine && i < _lines.length; i++) {
          _lines[i] = '  ${_lines[i]}';
        }
        _modified = true;
      case VimOperator.unindent:
        for (int i = startLine; i < endLine && i < _lines.length; i++) {
          if (_lines[i].startsWith('  ')) {
            _lines[i] = _lines[i].substring(2);
          } else if (_lines[i].startsWith('\t')) {
            _lines[i] = _lines[i].substring(1);
          }
        }
        _modified = true;
      case VimOperator.format:
        // Simple paragraph reflow — join lines and wrap at 80 cols
        final joined = removed.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        final wrapped = _wrapText(joined, 80);
        _lines.removeRange(startLine, endLine);
        _lines.insertAll(startLine, wrapped);
        _modified = true;
    }
    state.lastChange = '${count > 1 ? count : ""}${op.char}${op.char}';
  }

  void _applyOperatorWithMotion(VimOperator op, VimMotion motion, int count) {
    state.beginUndoGroup();
    state.pushUndo(_lines, state.cursor);
    final start = state.cursor;
    _moveCursor(motion, count);
    final end = state.cursor;

    final (sLine, sCol, eLine, eCol) = _orderPositions(start, end);

    switch (op) {
      case VimOperator.delete:
      case VimOperator.change:
        final text = _extractRange(sLine, sCol, eLine, eCol);
        state.register.delete(text);
        _deleteRange(sLine, sCol, eLine, eCol);
        state.cursor = CursorPosition(sLine, sCol);
        _modified = true;
        if (op == VimOperator.change) _enterInsert();
      case VimOperator.yank:
        final text = _extractRange(sLine, sCol, eLine, eCol);
        state.register.yank(text);
        state.cursor = CursorPosition(sLine, sCol);
      case VimOperator.indent:
        for (int i = sLine; i <= eLine && i < _lines.length; i++) {
          _lines[i] = '  ${_lines[i]}';
        }
        _modified = true;
      case VimOperator.unindent:
        for (int i = sLine; i <= eLine && i < _lines.length; i++) {
          if (_lines[i].startsWith('  ')) {
            _lines[i] = _lines[i].substring(2);
          }
        }
        _modified = true;
      case VimOperator.format:
        final textLines = _lines.sublist(sLine, eLine + 1);
        final joined = textLines
            .join(' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final wrapped = _wrapText(joined, 80);
        _lines.removeRange(sLine, eLine + 1);
        _lines.insertAll(sLine, wrapped);
        _modified = true;
    }
  }

  // -- Insert mode ----------------------------------------------------------

  void _enterInsert() {
    state.mode = VimMode.insert;
    state.resetPartial();
  }

  bool _handleInsert(String key) {
    if (key == 'Escape') {
      state.mode = VimMode.normal;
      final col = max(0, state.cursor.column - 1);
      state.cursor = state.cursor.copyWith(column: col);
      return true;
    }
    if (key == 'Backspace') {
      _backspace();
      return true;
    }
    if (key == 'Enter' || key == 'Return') {
      _insertNewline();
      return true;
    }
    if (key == 'Tab') {
      _insertText('  ');
      return true;
    }
    if (key.length == 1) {
      _insertText(key);
      return true;
    }
    return false;
  }

  void _insertText(String text) {
    state.pushUndo(_lines, state.cursor);
    final line = _currentLine();
    final col = state.cursor.column;
    _lines[state.cursor.line] =
        line.substring(0, col) + text + line.substring(col);
    state.cursor = state.cursor.copyWith(column: col + text.length);
    _modified = true;
    state.lastChange = 'i$text';
  }

  void _insertNewline() {
    state.pushUndo(_lines, state.cursor);
    final line = _currentLine();
    final col = state.cursor.column;
    final before = line.substring(0, col);
    final after = line.substring(col);
    // Detect indentation
    final indent = RegExp(r'^(\s*)').firstMatch(before)?.group(1) ?? '';
    _lines[state.cursor.line] = before;
    _lines.insert(state.cursor.line + 1, '$indent$after');
    state.cursor = CursorPosition(state.cursor.line + 1, indent.length);
    _modified = true;
  }

  void _backspace() {
    if (state.cursor.column > 0) {
      state.pushUndo(_lines, state.cursor);
      final line = _currentLine();
      final col = state.cursor.column;
      _lines[state.cursor.line] =
          line.substring(0, col - 1) + line.substring(col);
      state.cursor = state.cursor.copyWith(column: col - 1);
      _modified = true;
    } else if (state.cursor.line > 0) {
      state.pushUndo(_lines, state.cursor);
      final prevLen = _lineLength(state.cursor.line - 1);
      _lines[state.cursor.line - 1] += _currentLine();
      _lines.removeAt(state.cursor.line);
      state.cursor = CursorPosition(state.cursor.line - 1, prevLen);
      _modified = true;
    }
  }

  // -- Visual mode ----------------------------------------------------------

  bool _handleVisual(String key) {
    if (key == 'Escape') {
      state.mode = VimMode.normal;
      state.visualAnchor = null;
      state.resetPartial();
      return true;
    }

    final motion = _parseMotion(key);
    if (motion != null) {
      _moveCursor(motion, state.effectiveCount);
      state.resetPartial();
      return true;
    }

    switch (key) {
      case 'd':
      case 'x':
        _visualDelete();
        return true;
      case 'y':
        _visualYank();
        return true;
      case 'c':
        _visualDelete();
        _enterInsert();
        return true;
      case '>':
        _visualIndent(indent: true);
        return true;
      case '<':
        _visualIndent(indent: false);
        return true;
      case 'v':
        if (state.mode == VimMode.visual) {
          state.mode = VimMode.normal;
          state.visualAnchor = null;
        }
        return true;
      case 'V':
        if (state.mode == VimMode.visualLine) {
          state.mode = VimMode.normal;
          state.visualAnchor = null;
        } else {
          state.mode = VimMode.visualLine;
        }
        return true;
    }
    return false;
  }

  void _visualDelete() {
    if (state.visualAnchor == null) return;
    state.pushUndo(_lines, state.cursor);
    final anchor = state.visualAnchor!;
    if (state.mode == VimMode.visualLine) {
      final sLine = min(anchor.line, state.cursor.line);
      final eLine = max(anchor.line, state.cursor.line);
      final removed = _lines.sublist(sLine, eLine + 1).join('\n');
      state.register.delete(removed);
      _lines.removeRange(sLine, eLine + 1);
      if (_lines.isEmpty) _lines.add('');
      state.cursor = CursorPosition(min(sLine, _lines.length - 1), 0);
    } else {
      final (sL, sC, eL, eC) = _orderPositions(anchor, state.cursor);
      final text = _extractRange(sL, sC, eL, eC);
      state.register.delete(text);
      _deleteRange(sL, sC, eL, eC);
      state.cursor = CursorPosition(sL, sC);
    }
    state.mode = VimMode.normal;
    state.visualAnchor = null;
    _modified = true;
  }

  void _visualYank() {
    if (state.visualAnchor == null) return;
    final anchor = state.visualAnchor!;
    if (state.mode == VimMode.visualLine) {
      final sLine = min(anchor.line, state.cursor.line);
      final eLine = max(anchor.line, state.cursor.line);
      final text = _lines.sublist(sLine, eLine + 1).join('\n');
      state.register.yank(text);
    } else {
      final (sL, sC, eL, eC) = _orderPositions(anchor, state.cursor);
      state.register.yank(_extractRange(sL, sC, eL, eC));
    }
    state.mode = VimMode.normal;
    state.visualAnchor = null;
  }

  void _visualIndent({required bool indent}) {
    if (state.visualAnchor == null) return;
    state.pushUndo(_lines, state.cursor);
    final sLine = min(state.visualAnchor!.line, state.cursor.line);
    final eLine = max(state.visualAnchor!.line, state.cursor.line);
    for (int i = sLine; i <= eLine && i < _lines.length; i++) {
      if (indent) {
        _lines[i] = '  ${_lines[i]}';
      } else if (_lines[i].startsWith('  ')) {
        _lines[i] = _lines[i].substring(2);
      } else if (_lines[i].startsWith('\t')) {
        _lines[i] = _lines[i].substring(1);
      }
    }
    state.mode = VimMode.normal;
    state.visualAnchor = null;
    _modified = true;
  }

  // -- Command mode ---------------------------------------------------------

  bool _handleCommand(String key) {
    if (key == 'Escape') {
      state.mode = VimMode.normal;
      state.commandBuffer = '';
      return true;
    }
    if (key == 'Enter' || key == 'Return') {
      _executeCommand(state.commandBuffer);
      state.mode = VimMode.normal;
      state.commandBuffer = '';
      return true;
    }
    if (key == 'Backspace') {
      if (state.commandBuffer.isNotEmpty) {
        state.commandBuffer = state.commandBuffer.substring(
          0,
          state.commandBuffer.length - 1,
        );
      }
      if (state.commandBuffer.isEmpty) {
        state.mode = VimMode.normal;
      }
      return true;
    }
    if (key.length == 1) {
      state.commandBuffer += key;
      return true;
    }
    return false;
  }

  void _executeCommand(String raw) {
    // Handle search commands /pattern and ?pattern
    if (raw.startsWith('/')) {
      final pattern = raw.substring(1);
      if (pattern.isNotEmpty) {
        state.lastSearch = pattern;
        state.lastSearchForward = true;
        _performSearch(pattern, true);
      }
      return;
    }
    if (raw.startsWith('?')) {
      final pattern = raw.substring(1);
      if (pattern.isNotEmpty) {
        state.lastSearch = pattern;
        state.lastSearchForward = false;
        _performSearch(pattern, false);
      }
      return;
    }

    final cmd = parseVimCommand(raw);
    switch (cmd) {
      case SubstituteCommand c:
        _substitute(c);
      case GotoLineCommand c:
        final target = (c.line - 1).clamp(0, _lines.length - 1);
        state.cursor = CursorPosition(target, 0);
        _moveToFirstNonBlank();
      case SetCommand c:
        onStatusMessage?.call('set ${c.option}=${c.value ?? ""}');
      case ShellCommand c:
        onStatusMessage?.call('! ${c.command}');
      case WriteCommand _:
        onStatusMessage?.call('Buffer written');
      case QuitCommand _:
        onStatusMessage?.call('Quit');
      case WriteQuitCommand _:
        onStatusMessage?.call('Write and quit');
      case NoOpCommand c:
        if (c.raw.isNotEmpty) {
          onStatusMessage?.call('Unknown command: ${c.raw}');
        }
    }
  }

  // -- Replace mode ---------------------------------------------------------

  bool _handleReplace(String key) {
    if (key == 'Escape') {
      state.mode = VimMode.normal;
      return true;
    }
    if (key.length == 1) {
      state.pushUndo(_lines, state.cursor);
      final line = _currentLine();
      final col = state.cursor.column;
      if (col < line.length) {
        _lines[state.cursor.line] =
            line.substring(0, col) + key + line.substring(col + 1);
      } else {
        _lines[state.cursor.line] = line + key;
      }
      state.cursor = state.cursor.copyWith(
        column: min(col + 1, _lines[state.cursor.line].length - 1),
      );
      _modified = true;
      return true;
    }
    return false;
  }

  // -- Actions --------------------------------------------------------------

  void _deleteChars(int count) {
    state.pushUndo(_lines, state.cursor);
    final line = _currentLine();
    final col = state.cursor.column;
    final end = min(col + count, line.length);
    if (col < line.length) {
      final deleted = line.substring(col, end);
      state.register.delete(deleted);
      _lines[state.cursor.line] = line.substring(0, col) + line.substring(end);
      _modified = true;
      if (state.cursor.column >= _currentLineLength() &&
          state.cursor.column > 0) {
        state.cursor = state.cursor.copyWith(column: _currentLineLength() - 1);
      }
    }
    state.lastChange = '${count > 1 ? count : ""}x';
  }

  void _paste({required bool after}) {
    final content = state.register.paste(state.pendingRegister);
    if (content.isEmpty) return;
    state.pushUndo(_lines, state.cursor);
    if (content.contains('\n')) {
      // Linewise paste
      final newLines = content.split('\n');
      final insertAt = after ? state.cursor.line + 1 : state.cursor.line;
      _lines.insertAll(insertAt, newLines);
      state.cursor = CursorPosition(insertAt, 0);
      _moveToFirstNonBlank();
    } else {
      final line = _currentLine();
      final col = after ? state.cursor.column + 1 : state.cursor.column;
      _lines[state.cursor.line] =
          line.substring(0, col) + content + line.substring(col);
      state.cursor = state.cursor.copyWith(column: col + content.length - 1);
    }
    _modified = true;
  }

  void _openLineBelow() {
    state.pushUndo(_lines, state.cursor);
    final indent = RegExp(r'^(\s*)').firstMatch(_currentLine())?.group(1) ?? '';
    _lines.insert(state.cursor.line + 1, indent);
    state.cursor = CursorPosition(state.cursor.line + 1, indent.length);
    _enterInsert();
    _modified = true;
  }

  void _openLineAbove() {
    state.pushUndo(_lines, state.cursor);
    final indent = RegExp(r'^(\s*)').firstMatch(_currentLine())?.group(1) ?? '';
    _lines.insert(state.cursor.line, indent);
    state.cursor = CursorPosition(state.cursor.line, indent.length);
    _enterInsert();
    _modified = true;
  }

  void _undo() {
    final entry = state.popUndo();
    if (entry == null) {
      onStatusMessage?.call('Already at oldest change');
      return;
    }
    state.pushRedo(_lines, state.cursor);
    _lines
      ..clear()
      ..addAll(entry.lines);
    state.cursor = entry.cursor;
  }

  void _replaceChar(String ch) {
    state.pushUndo(_lines, state.cursor);
    final line = _currentLine();
    final col = state.cursor.column;
    if (col < line.length) {
      _lines[state.cursor.line] =
          line.substring(0, col) + ch + line.substring(col + 1);
      _modified = true;
    }
    state.lastChange = 'r$ch';
  }

  void _joinLines(int count) {
    state.pushUndo(_lines, state.cursor);
    for (int i = 0; i < count && state.cursor.line + 1 < _lines.length; i++) {
      final current = _lines[state.cursor.line].trimRight();
      final next = _lines[state.cursor.line + 1].trimLeft();
      _lines[state.cursor.line] = '$current $next';
      _lines.removeAt(state.cursor.line + 1);
    }
    _modified = true;
  }

  void _toggleCase() {
    state.pushUndo(_lines, state.cursor);
    final line = _currentLine();
    final col = state.cursor.column;
    if (col < line.length) {
      final ch = line[col];
      final toggled = ch == ch.toUpperCase()
          ? ch.toLowerCase()
          : ch.toUpperCase();
      _lines[state.cursor.line] =
          line.substring(0, col) + toggled + line.substring(col + 1);
      state.cursor = state.cursor.copyWith(
        column: min(col + 1, _currentLineLength() - 1),
      );
      _modified = true;
    }
  }

  void _repeatLastChange() {
    if (state.lastChange.isEmpty) return;
    for (final ch in state.lastChange.split('')) {
      handleKey(ch);
    }
  }

  // -- Search ---------------------------------------------------------------

  void _performSearch(String pattern, bool forward) {
    try {
      final re = RegExp(pattern, caseSensitive: true);
      final startLine = state.cursor.line;
      final startCol = state.cursor.column + 1;

      if (forward) {
        // Search from current position forward
        for (int i = 0; i < _lines.length; i++) {
          final lineIdx = (startLine + i) % _lines.length;
          final searchFrom = (i == 0) ? startCol : 0;
          final line = _lines[lineIdx];
          if (searchFrom >= line.length) continue;
          final match = re.firstMatch(line.substring(searchFrom));
          if (match != null) {
            state.cursor = CursorPosition(lineIdx, searchFrom + match.start);
            return;
          }
        }
      } else {
        for (int i = 0; i < _lines.length; i++) {
          final lineIdx = (startLine - i + _lines.length) % _lines.length;
          final line = _lines[lineIdx];
          final searchUntil = (i == 0) ? state.cursor.column : line.length;
          final matches = re.allMatches(line.substring(0, searchUntil));
          if (matches.isNotEmpty) {
            state.cursor = CursorPosition(lineIdx, matches.last.start);
            return;
          }
        }
      }
      onStatusMessage?.call('Pattern not found: $pattern');
    } catch (_) {
      onStatusMessage?.call('Invalid pattern: $pattern');
    }
  }

  void _searchNext({required bool forward}) {
    if (state.lastSearch.isEmpty) return;
    final dir = forward ? state.lastSearchForward : !state.lastSearchForward;
    _performSearch(state.lastSearch, dir);
  }

  void _findChar(String ch, bool forward, bool before, int count) {
    final line = _currentLine();
    int col = state.cursor.column;
    for (int i = 0; i < count; i++) {
      if (forward) {
        final idx = line.indexOf(ch, col + 1);
        if (idx < 0) return;
        col = before ? idx - 1 : idx;
      } else {
        final idx = line.lastIndexOf(ch, col - 1);
        if (idx < 0) return;
        col = before ? idx + 1 : idx;
      }
    }
    state.cursor = state.cursor.copyWith(column: col);
  }

  void _matchBracket() {
    const pairs = {'(': ')', ')': '(', '[': ']', ']': '[', '{': '}', '}': '{'};
    const openers = {'(', '[', '{'};
    final line = _currentLine();
    final col = state.cursor.column;
    if (col >= line.length) return;
    final ch = line[col];
    if (!pairs.containsKey(ch)) return;
    final target = pairs[ch]!;
    final forward = openers.contains(ch);
    int depth = 1;
    int l = state.cursor.line;
    int c = col;
    while (depth > 0) {
      if (forward) {
        c++;
        if (c >= _lines[l].length) {
          l++;
          c = 0;
          if (l >= _lines.length) return;
        }
      } else {
        c--;
        if (c < 0) {
          l--;
          if (l < 0) return;
          c = _lines[l].length - 1;
          if (c < 0) continue;
        }
      }
      if (_lines[l][c] == ch) depth++;
      if (_lines[l][c] == target) depth--;
    }
    state.cursor = CursorPosition(l, c);
  }

  // -- Substitute -----------------------------------------------------------

  void _substitute(SubstituteCommand cmd) {
    state.pushUndo(_lines, state.cursor);
    try {
      final re = RegExp(cmd.pattern);
      final line = _currentLine();
      String replaced;
      if (cmd.global) {
        replaced = line.replaceAll(re, cmd.replacement);
      } else {
        replaced = line.replaceFirst(re, cmd.replacement);
      }
      if (replaced != line) {
        _lines[state.cursor.line] = replaced;
        _modified = true;
      }
    } catch (_) {
      onStatusMessage?.call('Invalid pattern: ${cmd.pattern}');
    }
  }

  // -- Helpers --------------------------------------------------------------

  String _currentLine() =>
      state.cursor.line < _lines.length ? _lines[state.cursor.line] : '';
  int _currentLineLength() => _currentLine().length;
  int _lineLength(int line) =>
      line >= 0 && line < _lines.length ? _lines[line].length : 0;

  (int, int, int, int) _orderPositions(CursorPosition a, CursorPosition b) {
    if (a.line < b.line || (a.line == b.line && a.column <= b.column)) {
      return (a.line, a.column, b.line, b.column);
    }
    return (b.line, b.column, a.line, a.column);
  }

  String _extractRange(int sLine, int sCol, int eLine, int eCol) {
    if (sLine == eLine) {
      final line = _lines[sLine];
      return line.substring(sCol, min(eCol + 1, line.length));
    }
    final buf = StringBuffer();
    buf.write(_lines[sLine].substring(sCol));
    for (int i = sLine + 1; i < eLine; i++) {
      buf.write('\n${_lines[i]}');
    }
    buf.write(
      '\n${_lines[eLine].substring(0, min(eCol + 1, _lines[eLine].length))}',
    );
    return buf.toString();
  }

  void _deleteRange(int sLine, int sCol, int eLine, int eCol) {
    if (sLine == eLine) {
      final line = _lines[sLine];
      _lines[sLine] =
          line.substring(0, sCol) + line.substring(min(eCol + 1, line.length));
    } else {
      final before = _lines[sLine].substring(0, sCol);
      final after = _lines[eLine].substring(
        min(eCol + 1, _lines[eLine].length),
      );
      _lines[sLine] = before + after;
      _lines.removeRange(sLine + 1, eLine + 1);
    }
    if (_lines.isEmpty) _lines.add('');
  }

  List<String> _wrapText(String text, int width) {
    if (text.length <= width) return [text];
    final result = <String>[];
    var remaining = text;
    while (remaining.length > width) {
      int breakAt = remaining.lastIndexOf(' ', width);
      if (breakAt <= 0) breakAt = width;
      result.add(remaining.substring(0, breakAt).trimRight());
      remaining = remaining.substring(breakAt).trimLeft();
    }
    if (remaining.isNotEmpty) result.add(remaining);
    return result;
  }
}
