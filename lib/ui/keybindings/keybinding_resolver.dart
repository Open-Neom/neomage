// Keybinding resolver — comprehensive port of neomage/src/keybindings/.
// Stateful chord resolution, conflict detection, platform-specific bindings,
// user config loading/validation, and shortcut display formatting.

import 'package:neomage/core/platform/neomage_io.dart' show Platform;

import 'keybinding_types.dart';

// ════════════════════════════════════════════════════════════════════════════
// Reserved shortcuts
// ════════════════════════════════════════════════════════════════════════════

/// Severity of a reserved shortcut warning.
enum ReservedSeverity { error, warning }

/// A shortcut that is reserved by the OS, terminal, or application.
class ReservedShortcut {
  final String key;
  final String reason;
  final ReservedSeverity severity;

  const ReservedShortcut({
    required this.key,
    required this.reason,
    required this.severity,
  });
}

/// Shortcuts that cannot be rebound — hardcoded in the application.
const List<ReservedShortcut> nonRebindable = [
  ReservedShortcut(
    key: 'ctrl+c',
    reason: 'Cannot be rebound - used for interrupt/exit (hardcoded)',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'ctrl+d',
    reason: 'Cannot be rebound - used for exit (hardcoded)',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'ctrl+m',
    reason:
        'Cannot be rebound - identical to Enter in terminals (both send CR)',
    severity: ReservedSeverity.error,
  ),
];

/// Terminal control shortcuts intercepted by the terminal / OS.
const List<ReservedShortcut> terminalReserved = [
  ReservedShortcut(
    key: 'ctrl+z',
    reason: 'Unix process suspend (SIGTSTP)',
    severity: ReservedSeverity.warning,
  ),
  ReservedShortcut(
    key: r'ctrl+\',
    reason: 'Terminal quit signal (SIGQUIT)',
    severity: ReservedSeverity.error,
  ),
];

/// macOS-specific shortcuts intercepted by the OS.
const List<ReservedShortcut> macosReserved = [
  ReservedShortcut(
    key: 'cmd+c',
    reason: 'macOS system copy',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'cmd+v',
    reason: 'macOS system paste',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'cmd+x',
    reason: 'macOS system cut',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'cmd+q',
    reason: 'macOS quit application',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'cmd+w',
    reason: 'macOS close window/tab',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'cmd+tab',
    reason: 'macOS app switcher',
    severity: ReservedSeverity.error,
  ),
  ReservedShortcut(
    key: 'cmd+space',
    reason: 'macOS Spotlight',
    severity: ReservedSeverity.error,
  ),
];

/// Returns all reserved shortcuts for the current platform.
List<ReservedShortcut> getReservedShortcuts() {
  final reserved = <ReservedShortcut>[...nonRebindable, ...terminalReserved];
  if (Platform.isMacOS) {
    reserved.addAll(macosReserved);
  }
  return reserved;
}

/// Normalize a key string for comparison (lowercase, sorted modifiers).
/// Chords (space-separated steps) are normalized per-step.
String normalizeKeyForComparison(String key) {
  return key.trim().split(RegExp(r'\s+')).map(_normalizeStep).join(' ');
}

String _normalizeStep(String step) {
  final parts = step.split('+');
  final modifiers = <String>[];
  var mainKey = '';

  for (final part in parts) {
    final lower = part.trim().toLowerCase();
    switch (lower) {
      case 'ctrl' || 'control':
        modifiers.add('ctrl');
      case 'alt' || 'opt' || 'option':
        modifiers.add('alt');
      case 'meta':
        modifiers.add('meta');
      case 'cmd' || 'command':
        modifiers.add('cmd');
      case 'shift':
        modifiers.add('shift');
      default:
        mainKey = lower;
    }
  }

  modifiers.sort();
  return [...modifiers, mainKey].join('+');
}

// ════════════════════════════════════════════════════════════════════════════
// Validation types
// ════════════════════════════════════════════════════════════════════════════

/// Types of validation issues.
enum KeybindingWarningType {
  parseError,
  duplicate,
  reserved,
  invalidContext,
  invalidAction,
}

/// A warning or error about a keybinding configuration issue.
class KeybindingWarning {
  final KeybindingWarningType type;
  final ReservedSeverity severity;
  final String message;
  final String? key;
  final String? context;
  final String? action;
  final String? suggestion;

  const KeybindingWarning({
    required this.type,
    required this.severity,
    required this.message,
    this.key,
    this.context,
    this.action,
    this.suggestion,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// Keybinding block — JSON config format
// ════════════════════════════════════════════════════════════════════════════

/// A block of keybindings for a specific context (JSON config format).
class KeybindingBlock {
  final String context;
  final Map<String, String?> bindings;

  const KeybindingBlock({required this.context, required this.bindings});

  factory KeybindingBlock.fromJson(Map<String, dynamic> json) {
    final bindings = <String, String?>{};
    final raw = json['bindings'] as Map<String, dynamic>? ?? {};
    for (final entry in raw.entries) {
      bindings[entry.key] = entry.value as String?;
    }
    return KeybindingBlock(
      context: json['context'] as String,
      bindings: bindings,
    );
  }

  Map<String, dynamic> toJson() => {'context': context, 'bindings': bindings};
}

// ════════════════════════════════════════════════════════════════════════════
// Resolve results
// ════════════════════════════════════════════════════════════════════════════

/// Result types for simple (no-chord) resolution.
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

/// Result types for chord-aware resolution.
sealed class ChordResolveResult {
  const ChordResolveResult();
}

class ChordMatchResult extends ChordResolveResult {
  final String action;
  const ChordMatchResult(this.action);
}

class ChordNoMatchResult extends ChordResolveResult {
  const ChordNoMatchResult();
}

class ChordUnboundResult extends ChordResolveResult {
  const ChordUnboundResult();
}

class ChordStartedResult extends ChordResolveResult {
  final List<ParsedKeystroke> pending;
  const ChordStartedResult(this.pending);
}

class ChordCancelledResult extends ChordResolveResult {
  const ChordCancelledResult();
}

// ════════════════════════════════════════════════════════════════════════════
// Keystroke comparison
// ════════════════════════════════════════════════════════════════════════════

/// Compare two ParsedKeystrokes for equality.
/// Collapses alt/meta into one logical modifier — legacy terminals cannot
/// distinguish them, so "alt+k" and "meta+k" are the same key.
/// Super (cmd/win) is distinct — only arrives via kitty keyboard protocol.
bool keystrokesEqual(ParsedKeystroke a, ParsedKeystroke b) {
  return a.key == b.key &&
      a.ctrl == b.ctrl &&
      a.shift == b.shift &&
      (a.alt || a.meta) == (b.alt || b.meta) &&
      a.superKey == b.superKey;
}

/// Check if a chord prefix matches the beginning of a binding's chord.
bool chordPrefixMatches(List<ParsedKeystroke> prefix, ParsedBinding binding) {
  if (prefix.length >= binding.chord.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (!keystrokesEqual(prefix[i], binding.chord[i])) return false;
  }
  return true;
}

/// Check if a full chord matches a binding's chord exactly.
bool chordExactlyMatches(List<ParsedKeystroke> chord, ParsedBinding binding) {
  if (chord.length != binding.chord.length) return false;
  for (var i = 0; i < chord.length; i++) {
    if (!keystrokesEqual(chord[i], binding.chord[i])) return false;
  }
  return true;
}

// ════════════════════════════════════════════════════════════════════════════
// Parser helpers
// ════════════════════════════════════════════════════════════════════════════

/// Convert a chord to its canonical string representation.
String chordToString(List<ParsedKeystroke> chord) {
  return chord.map(keystrokeToString).join(' ');
}

/// Convert a ParsedKeystroke to its canonical string representation.
String keystrokeToString(ParsedKeystroke ks) {
  final parts = <String>[];
  if (ks.ctrl) parts.add('ctrl');
  if (ks.alt) parts.add('alt');
  if (ks.shift) parts.add('shift');
  if (ks.meta) parts.add('meta');
  if (ks.superKey) parts.add('cmd');
  parts.add(_keyToDisplayName(ks.key));
  return parts.join('+');
}

/// Convert a ParsedKeystroke to a platform-appropriate display string.
String keystrokeToDisplayString(
  ParsedKeystroke ks, {
  String platform = 'linux',
}) {
  final parts = <String>[];
  if (ks.ctrl) parts.add('ctrl');
  if (ks.alt || ks.meta) {
    parts.add(platform == 'macos' ? 'opt' : 'alt');
  }
  if (ks.shift) parts.add('shift');
  if (ks.superKey) {
    parts.add(platform == 'macos' ? 'cmd' : 'super');
  }
  parts.add(_keyToDisplayName(ks.key));
  return parts.join('+');
}

/// Convert a chord to a platform-appropriate display string.
String chordToDisplayString(
  List<ParsedKeystroke> chord, {
  String platform = 'linux',
}) {
  return chord
      .map((ks) => keystrokeToDisplayString(ks, platform: platform))
      .join(' ');
}

/// Map internal key names to human-readable display names.
String _keyToDisplayName(String key) => switch (key) {
  'escape' => 'Esc',
  ' ' || 'space' => 'Space',
  'tab' => 'tab',
  'enter' => 'Enter',
  'backspace' => 'Backspace',
  'delete' => 'Delete',
  'up' => '\u2191',
  'down' => '\u2193',
  'left' => '\u2190',
  'right' => '\u2192',
  'pageup' => 'PageUp',
  'pagedown' => 'PageDown',
  'home' => 'Home',
  'end' => 'End',
  _ => key,
};

// ════════════════════════════════════════════════════════════════════════════
// Block-level parser
// ════════════════════════════════════════════════════════════════════════════

/// Parse keybinding blocks (from JSON config) into a flat list of ParsedBindings.
List<ParsedBinding> parseBindingBlocks(List<KeybindingBlock> blocks) {
  final bindings = <ParsedBinding>[];
  for (final block in blocks) {
    final context = _contextFromString(block.context);
    if (context == null) continue;
    for (final entry in block.bindings.entries) {
      bindings.add(
        ParsedBinding(
          chord: parseChord(entry.key),
          action: entry.value,
          context: context,
        ),
      );
    }
  }
  return bindings;
}

/// Map context string to enum (case-sensitive matching).
KeybindingContext? _contextFromString(String name) => switch (name) {
  'Global' => KeybindingContext.global,
  'Chat' => KeybindingContext.chat,
  'Autocomplete' => KeybindingContext.autocomplete,
  'Confirmation' => KeybindingContext.confirmation,
  'Help' => KeybindingContext.help,
  'Transcript' => KeybindingContext.transcript,
  'HistorySearch' => KeybindingContext.historySearch,
  'Task' => KeybindingContext.task,
  'ThemePicker' => KeybindingContext.themePicker,
  'Settings' => KeybindingContext.settings,
  'Tabs' => KeybindingContext.tabs,
  'Attachments' => KeybindingContext.attachments,
  'Footer' => KeybindingContext.footer,
  'MessageSelector' => KeybindingContext.messageSelector,
  'DiffDialog' => KeybindingContext.diffDialog,
  'ModelPicker' => KeybindingContext.modelPicker,
  'Select' => KeybindingContext.select,
  'Plugin' => KeybindingContext.plugin,
  'Scroll' => KeybindingContext.scroll,
  'MessageActions' => KeybindingContext.messageActions,
  _ => null,
};

// ════════════════════════════════════════════════════════════════════════════
// Validation
// ════════════════════════════════════════════════════════════════════════════

/// Valid context names for keybindings.
const List<String> validContextNames = [
  'Global',
  'Chat',
  'Autocomplete',
  'Confirmation',
  'Help',
  'Transcript',
  'HistorySearch',
  'Task',
  'ThemePicker',
  'Settings',
  'Tabs',
  'Attachments',
  'Footer',
  'MessageSelector',
  'DiffDialog',
  'ModelPicker',
  'Select',
  'Plugin',
  'Scroll',
  'MessageActions',
];

/// Human-readable descriptions for each keybinding context.
const Map<String, String> contextDescriptions = {
  'Global': 'Active everywhere, regardless of focus',
  'Chat': 'When the chat input is focused',
  'Autocomplete': 'When autocomplete menu is visible',
  'Confirmation': 'When a confirmation/permission dialog is shown',
  'Help': 'When the help overlay is open',
  'Transcript': 'When viewing the transcript',
  'HistorySearch': 'When searching command history (ctrl+r)',
  'Task': 'When a task/agent is running in the foreground',
  'ThemePicker': 'When the theme picker is open',
  'Settings': 'When the settings menu is open',
  'Tabs': 'When tab navigation is active',
  'Attachments': 'When navigating image attachments in a select dialog',
  'Footer': 'When footer indicators are focused',
  'MessageSelector': 'When the message selector (rewind) is open',
  'DiffDialog': 'When the diff dialog is open',
  'ModelPicker': 'When the model picker is open',
  'Select': 'When a select/list component is focused',
  'Plugin': 'When the plugin dialog is open',
  'Scroll': 'When scrollable content is visible',
  'MessageActions': 'When message action cursor is active',
};

/// Validate a single keystroke string.
KeybindingWarning? validateKeystroke(String keystroke) {
  final parts = keystroke.toLowerCase().split('+');
  for (final part in parts) {
    if (part.trim().isEmpty) {
      return KeybindingWarning(
        type: KeybindingWarningType.parseError,
        severity: ReservedSeverity.error,
        message: 'Empty key part in "$keystroke"',
        key: keystroke,
        suggestion: 'Remove extra "+" characters',
      );
    }
  }
  final parsed = parseKeystroke(keystroke);
  if (parsed.key.isEmpty &&
      !parsed.ctrl &&
      !parsed.alt &&
      !parsed.shift &&
      !parsed.meta) {
    return KeybindingWarning(
      type: KeybindingWarningType.parseError,
      severity: ReservedSeverity.error,
      message: 'Could not parse keystroke "$keystroke"',
      key: keystroke,
    );
  }
  return null;
}

/// Validate user keybinding config structure.
List<KeybindingWarning> validateUserConfig(List<dynamic> userBlocks) {
  final warnings = <KeybindingWarning>[];
  for (var i = 0; i < userBlocks.length; i++) {
    warnings.addAll(_validateBlock(userBlocks[i], i));
  }
  return warnings;
}

List<KeybindingWarning> _validateBlock(dynamic block, int blockIndex) {
  final warnings = <KeybindingWarning>[];
  if (block is! Map<String, dynamic>) {
    warnings.add(
      KeybindingWarning(
        type: KeybindingWarningType.parseError,
        severity: ReservedSeverity.error,
        message: 'Keybinding block ${blockIndex + 1} is not an object',
      ),
    );
    return warnings;
  }

  final rawContext = block['context'];
  String? contextName;
  if (rawContext is! String) {
    warnings.add(
      KeybindingWarning(
        type: KeybindingWarningType.parseError,
        severity: ReservedSeverity.error,
        message: 'Keybinding block ${blockIndex + 1} missing "context" field',
      ),
    );
  } else if (!validContextNames.contains(rawContext)) {
    warnings.add(
      KeybindingWarning(
        type: KeybindingWarningType.invalidContext,
        severity: ReservedSeverity.error,
        message: 'Unknown context "$rawContext"',
        context: rawContext,
        suggestion: 'Valid contexts: ${validContextNames.join(', ')}',
      ),
    );
  } else {
    contextName = rawContext;
  }

  final bindings = block['bindings'];
  if (bindings is! Map<String, dynamic>) {
    warnings.add(
      KeybindingWarning(
        type: KeybindingWarningType.parseError,
        severity: ReservedSeverity.error,
        message: 'Keybinding block ${blockIndex + 1} missing "bindings" field',
      ),
    );
    return warnings;
  }

  for (final entry in bindings.entries) {
    final keyError = validateKeystroke(entry.key);
    if (keyError != null) {
      warnings.add(
        KeybindingWarning(
          type: keyError.type,
          severity: keyError.severity,
          message: keyError.message,
          key: keyError.key,
          context: contextName,
          suggestion: keyError.suggestion,
        ),
      );
    }

    final action = entry.value;
    if (action != null && action is! String) {
      warnings.add(
        KeybindingWarning(
          type: KeybindingWarningType.invalidAction,
          severity: ReservedSeverity.error,
          message:
              'Invalid action for "${entry.key}": must be a string or null',
          key: entry.key,
          context: contextName,
        ),
      );
    } else if (action is String && action.startsWith('command:')) {
      if (!RegExp(r'^command:[a-zA-Z0-9:\-_]+$').hasMatch(action)) {
        warnings.add(
          KeybindingWarning(
            type: KeybindingWarningType.invalidAction,
            severity: ReservedSeverity.warning,
            message:
                'Invalid command binding "$action" for "${entry.key}": command name may only contain alphanumeric characters, colons, hyphens, and underscores',
            key: entry.key,
            context: contextName,
            action: action,
          ),
        );
      }
      if (contextName != null && contextName != 'Chat') {
        warnings.add(
          KeybindingWarning(
            type: KeybindingWarningType.invalidAction,
            severity: ReservedSeverity.warning,
            message:
                'Command binding "$action" must be in "Chat" context, not "$contextName"',
            key: entry.key,
            context: contextName,
            action: action,
            suggestion: 'Move this binding to a block with "context": "Chat"',
          ),
        );
      }
    }
  }

  return warnings;
}

/// Check for duplicate bindings within the same context.
List<KeybindingWarning> checkDuplicates(List<KeybindingBlock> blocks) {
  final warnings = <KeybindingWarning>[];
  final seenByContext = <String, Map<String, String>>{};

  for (final block in blocks) {
    final contextMap = seenByContext.putIfAbsent(block.context, () => {});
    for (final entry in block.bindings.entries) {
      final normalizedKey = normalizeKeyForComparison(entry.key);
      final existingAction = contextMap[normalizedKey];
      if (existingAction != null && existingAction != (entry.value ?? 'null')) {
        warnings.add(
          KeybindingWarning(
            type: KeybindingWarningType.duplicate,
            severity: ReservedSeverity.warning,
            message:
                'Duplicate binding "${entry.key}" in ${block.context} context',
            key: entry.key,
            context: block.context,
            action: entry.value ?? 'null (unbind)',
            suggestion:
                'Previously bound to "$existingAction". Only the last binding will be used.',
          ),
        );
      }
      contextMap[normalizedKey] = entry.value ?? 'null';
    }
  }

  return warnings;
}

/// Check for reserved shortcuts that may not work.
List<KeybindingWarning> checkReservedShortcuts(List<ParsedBinding> bindings) {
  final warnings = <KeybindingWarning>[];
  final reserved = getReservedShortcuts();

  for (final binding in bindings) {
    final keyDisplay = chordToString(binding.chord);
    final normalizedKey = normalizeKeyForComparison(keyDisplay);
    for (final res in reserved) {
      if (normalizeKeyForComparison(res.key) == normalizedKey) {
        warnings.add(
          KeybindingWarning(
            type: KeybindingWarningType.reserved,
            severity: res.severity == ReservedSeverity.error
                ? ReservedSeverity.error
                : ReservedSeverity.warning,
            message: '"$keyDisplay" may not work: ${res.reason}',
            key: keyDisplay,
            context: binding.context.name,
            action: binding.action,
          ),
        );
      }
    }
  }

  return warnings;
}

/// Run all validations and return combined, deduplicated warnings.
List<KeybindingWarning> validateBindings(
  List<dynamic> userBlocks,
  List<ParsedBinding> parsedBindings,
) {
  final warnings = <KeybindingWarning>[];
  warnings.addAll(validateUserConfig(userBlocks));

  final typed = <KeybindingBlock>[];
  for (final block in userBlocks) {
    if (block is Map<String, dynamic> &&
        block['context'] is String &&
        block['bindings'] is Map<String, dynamic>) {
      typed.add(KeybindingBlock.fromJson(block));
    }
  }
  if (typed.isNotEmpty) {
    warnings.addAll(checkDuplicates(typed));
    final userParsed = parseBindingBlocks(typed);
    warnings.addAll(checkReservedShortcuts(userParsed));
  }

  // Deduplicate warnings.
  final seen = <String>{};
  return warnings.where((w) {
    final key = '${w.type}:${w.key}:${w.context}';
    if (seen.contains(key)) return false;
    seen.add(key);
    return true;
  }).toList();
}

/// Format a warning for display.
String formatWarning(KeybindingWarning warning) {
  final icon = warning.severity == ReservedSeverity.error ? '\u2717' : '\u26A0';
  var msg = '$icon Keybinding ${warning.severity.name}: ${warning.message}';
  if (warning.suggestion != null) {
    msg += '\n  ${warning.suggestion}';
  }
  return msg;
}

/// Format multiple warnings for display.
String formatWarnings(List<KeybindingWarning> warnings) {
  if (warnings.isEmpty) return '';
  final errors = warnings
      .where((w) => w.severity == ReservedSeverity.error)
      .toList();
  final warns = warnings
      .where((w) => w.severity == ReservedSeverity.warning)
      .toList();
  final lines = <String>[];
  if (errors.isNotEmpty) {
    lines.add(
      'Found ${errors.length} keybinding error${errors.length == 1 ? '' : 's'}:',
    );
    for (final e in errors) {
      lines.add(formatWarning(e));
    }
  }
  if (warns.isNotEmpty) {
    if (lines.isNotEmpty) lines.add('');
    lines.add(
      'Found ${warns.length} keybinding warning${warns.length == 1 ? '' : 's'}:',
    );
    for (final w in warns) {
      lines.add(formatWarning(w));
    }
  }
  return lines.join('\n');
}

// ════════════════════════════════════════════════════════════════════════════
// KeybindingResolver — stateful chord resolution
// ════════════════════════════════════════════════════════════════════════════

/// Keybinding resolver — resolves keystrokes to actions with chord support,
/// conflict detection, and context-aware binding lookup.
class KeybindingResolver {
  final List<ParsedBinding> _bindings = [];
  List<ParsedKeystroke>? _pendingChord;

  /// Register bindings (later registrations take priority).
  void registerBindings(List<ParsedBinding> bindings) {
    _bindings.addAll(bindings);
  }

  /// Replace all bindings with a new set.
  void setBindings(List<ParsedBinding> bindings) {
    _bindings
      ..clear()
      ..addAll(bindings);
    _pendingChord = null;
  }

  /// Clear all bindings.
  void clearBindings() {
    _bindings.clear();
    _pendingChord = null;
  }

  /// The current registered bindings.
  List<ParsedBinding> get bindings => List.unmodifiable(_bindings);

  /// Whether a chord is in progress.
  bool get isChordPending => _pendingChord != null;

  /// The current pending chord keystrokes (null if not in a chord).
  List<ParsedKeystroke>? get pendingChord => _pendingChord;

  /// Cancel any pending chord.
  void cancelChord() {
    _pendingChord = null;
  }

  /// Set the pending chord state externally (for context-based coordination).
  void setPendingChord(List<ParsedKeystroke>? pending) {
    _pendingChord = pending;
  }

  // ── Simple resolution (single-keystroke, no chord state) ──

  /// Resolve a keystroke in a list of active contexts.
  /// Pure single-keystroke matching — last registered binding wins.
  ResolveResult resolveKey(
    ParsedKeystroke keystroke,
    List<KeybindingContext> activeContexts,
  ) {
    final ctxSet = activeContexts.toSet();
    ParsedBinding? match;

    for (final binding in _bindings) {
      if (binding.chord.length != 1) continue;
      if (!ctxSet.contains(binding.context)) continue;
      if (keystrokesEqual(binding.chord.first, keystroke)) {
        match = binding;
      }
    }

    if (match == null) return const NoMatchResult();
    if (match.action == null) return const UnboundResult();
    return MatchResult(match.action!);
  }

  // ── Chord-aware resolution ──

  /// Resolve a keystroke with chord state support.
  /// Handles multi-keystroke chord bindings like "ctrl+k ctrl+s".
  ChordResolveResult resolveKeyWithChordState(
    ParsedKeystroke keystroke,
    List<KeybindingContext> activeContexts,
  ) {
    // Cancel chord on escape.
    if (keystroke.key == 'escape' && _pendingChord != null) {
      _pendingChord = null;
      return const ChordCancelledResult();
    }

    // Build the full chord sequence to test.
    final testChord = _pendingChord != null
        ? [..._pendingChord!, keystroke]
        : [keystroke];

    // Filter bindings by active contexts.
    final ctxSet = activeContexts.toSet();
    final contextBindings = _bindings
        .where((b) => ctxSet.contains(b.context))
        .toList();

    // Check if this could be a prefix for longer chords. Track null-overrides
    // to avoid entering chord-wait for bindings that have been unbound.
    final chordWinners = <String, String?>{};
    for (final binding in contextBindings) {
      if (binding.chord.length > testChord.length &&
          chordPrefixMatches(testChord, binding)) {
        chordWinners[chordToString(binding.chord)] = binding.action;
      }
    }
    var hasLongerChords = false;
    for (final action in chordWinners.values) {
      if (action != null) {
        hasLongerChords = true;
        break;
      }
    }

    // If this keystroke could start a longer chord, prefer that.
    if (hasLongerChords) {
      _pendingChord = testChord;
      return ChordStartedResult(testChord);
    }

    // Check for exact matches (last one wins).
    ParsedBinding? exactMatch;
    for (final binding in contextBindings) {
      if (chordExactlyMatches(testChord, binding)) {
        exactMatch = binding;
      }
    }

    if (exactMatch != null) {
      _pendingChord = null;
      if (exactMatch.action == null) return const ChordUnboundResult();
      return ChordMatchResult(exactMatch.action!);
    }

    // No match and no potential longer chords.
    if (_pendingChord != null) {
      _pendingChord = null;
      return const ChordCancelledResult();
    }

    return const ChordNoMatchResult();
  }

  // ── Display text helpers ──

  /// Get display text for an action in a context (e.g. "ctrl+t").
  /// Searches in reverse order so user overrides take precedence.
  String? getBindingDisplayText(String action, KeybindingContext context) {
    for (var i = _bindings.length - 1; i >= 0; i--) {
      final binding = _bindings[i];
      if (binding.action == action && binding.context == context) {
        return chordToString(binding.chord);
      }
    }
    return null;
  }

  /// Get display text with platform-appropriate formatting.
  String? getBindingDisplayTextPlatform(
    String action,
    KeybindingContext context, {
    String platform = 'linux',
  }) {
    for (var i = _bindings.length - 1; i >= 0; i--) {
      final binding = _bindings[i];
      if (binding.action == action && binding.context == context) {
        return chordToDisplayString(binding.chord, platform: platform);
      }
    }
    return null;
  }

  /// Get shortcut display text with fallback.
  String getShortcutDisplay(
    String action,
    KeybindingContext context,
    String fallback,
  ) {
    return getBindingDisplayText(action, context) ?? fallback;
  }

  /// Get all bindings for a context.
  List<ParsedBinding> getBindingsForContext(KeybindingContext context) {
    return _bindings
        .where(
          (b) => b.context == context || b.context == KeybindingContext.global,
        )
        .toList();
  }

  /// Get all bindings for multiple contexts (union).
  List<ParsedBinding> getBindingsForContexts(List<KeybindingContext> contexts) {
    final ctxSet = contexts.toSet();
    return _bindings.where((b) => ctxSet.contains(b.context)).toList();
  }

  /// Find conflicting bindings for a given keystroke in a context.
  List<ParsedBinding> findConflicts(
    String keyString,
    KeybindingContext context,
  ) {
    final targetChord = parseChord(keyString);
    final conflicts = <ParsedBinding>[];
    for (final binding in _bindings) {
      if (binding.context != context &&
          binding.context != KeybindingContext.global) {
        continue;
      }
      if (binding.chord.length != targetChord.length) continue;
      var matches = true;
      for (var i = 0; i < targetChord.length; i++) {
        if (!keystrokesEqual(targetChord[i], binding.chord[i])) {
          matches = false;
          break;
        }
      }
      if (matches) conflicts.add(binding);
    }
    return conflicts;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Template generator
// ════════════════════════════════════════════════════════════════════════════

/// Filter out reserved shortcuts that cannot be rebound.
List<KeybindingBlock> filterReservedShortcuts(List<KeybindingBlock> blocks) {
  final reservedKeys = nonRebindable
      .map((r) => normalizeKeyForComparison(r.key))
      .toSet();
  return blocks
      .map((block) {
        final filtered = <String, String?>{};
        for (final entry in block.bindings.entries) {
          if (!reservedKeys.contains(normalizeKeyForComparison(entry.key))) {
            filtered[entry.key] = entry.value;
          }
        }
        return KeybindingBlock(context: block.context, bindings: filtered);
      })
      .where((block) => block.bindings.isNotEmpty)
      .toList();
}
