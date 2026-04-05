// Keybinding types — port of neomage/src/keybindings/.
// Keystroke parsing, chord state machine, and binding resolution.

/// A parsed keystroke.
class ParsedKeystroke {
  final String key;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;
  final bool superKey;

  const ParsedKeystroke({
    required this.key,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
    this.superKey = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ParsedKeystroke &&
      key == other.key &&
      ctrl == other.ctrl &&
      alt == other.alt &&
      shift == other.shift &&
      meta == other.meta &&
      superKey == other.superKey;

  @override
  int get hashCode => Object.hash(key, ctrl, alt, shift, meta, superKey);

  @override
  String toString() => toDisplayString();

  /// Display string for the keystroke (platform-aware).
  String toDisplayString({bool macOS = true}) {
    final parts = <String>[];
    if (ctrl) parts.add(macOS ? '\u2303' : 'Ctrl');
    if (alt) parts.add(macOS ? '\u2325' : 'Alt');
    if (shift) parts.add(macOS ? '\u21E7' : 'Shift');
    if (meta) parts.add(macOS ? '\u2318' : 'Super');
    parts.add(_displayKey(key));
    return parts.join(macOS ? '' : '+');
  }
}

/// A chord — sequence of keystrokes (e.g., Ctrl+K followed by Ctrl+S).
typedef Chord = List<ParsedKeystroke>;

/// Keybinding contexts.
enum KeybindingContext {
  global,
  chat,
  autocomplete,
  commandPalette,
  permissionDialog,
  input,
  diffView,
  filePreview,
  planMode,
  agentView,
  settingsView,
  confirmation,
  help,
  transcript,
  historySearch,
  task,
  themePicker,
  settings,
  tabs,
  attachments,
  footer,
  messageSelector,
  diffDialog,
  modelPicker,
  select,
  plugin,
  scroll,
  messageActions,
}

/// A resolved keybinding.
class ParsedBinding {
  final Chord chord;
  final String? action;
  final KeybindingContext context;

  const ParsedBinding({
    required this.chord,
    this.action,
    required this.context,
  });
}

/// Result of key resolution.
sealed class ResolveResult {
  const ResolveResult();
}

class MatchResult extends ResolveResult {
  final String action;
  const MatchResult(this.action);
}

class NoMatchResult extends ResolveResult {
  const NoMatchResult();
}

class UnboundResult extends ResolveResult {
  const UnboundResult();
}

class ChordStartedResult extends ResolveResult {
  final List<ParsedKeystroke> pending;
  const ChordStartedResult(this.pending);
}

class ChordCancelledResult extends ResolveResult {
  const ChordCancelledResult();
}

// ── Parsing ──

/// Parse a keystroke string like "ctrl+shift+k".
ParsedKeystroke parseKeystroke(String input) {
  final parts = input.toLowerCase().split('+').map((s) => s.trim()).toList();

  var ctrl = false;
  var alt = false;
  var shift = false;
  var meta = false;
  var key = '';

  for (final part in parts) {
    switch (part) {
      case 'ctrl' || 'control':
        ctrl = true;
      case 'alt' || 'opt' || 'option':
        alt = true;
      case 'shift':
        shift = true;
      case 'meta' || 'cmd' || 'command' || 'super' || 'win':
        meta = true;
      default:
        key = _normalizeKeyName(part);
    }
  }

  return ParsedKeystroke(
    key: key,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    meta: meta,
  );
}

/// Parse a chord string like "ctrl+k ctrl+s".
Chord parseChord(String input) {
  return input
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .map(parseKeystroke)
      .toList();
}

/// Check if two keystrokes match (handles alt/meta equivalence).
bool keystrokesEqual(ParsedKeystroke a, ParsedKeystroke b) {
  return a.key == b.key &&
      a.ctrl == b.ctrl &&
      (a.alt == b.alt || a.meta == b.meta) && // Alt and meta equivalent
      a.shift == b.shift;
}

String _normalizeKeyName(String name) => switch (name) {
  'escape' || 'esc' => 'escape',
  'enter' || 'return' => 'enter',
  'space' || ' ' => 'space',
  'backspace' || 'delete' => 'backspace',
  'tab' => 'tab',
  'up' || 'arrowup' => 'up',
  'down' || 'arrowdown' => 'down',
  'left' || 'arrowleft' => 'left',
  'right' || 'arrowright' => 'right',
  'home' => 'home',
  'end' => 'end',
  'pageup' => 'pageup',
  'pagedown' => 'pagedown',
  _ => name,
};

String _displayKey(String key) => switch (key) {
  'escape' => 'Esc',
  'enter' => '\u23CE',
  'space' => 'Space',
  'backspace' => '\u232B',
  'tab' => '\u21E5',
  'up' => '\u2191',
  'down' => '\u2193',
  'left' => '\u2190',
  'right' => '\u2192',
  _ => key.length == 1 ? key.toUpperCase() : key,
};
