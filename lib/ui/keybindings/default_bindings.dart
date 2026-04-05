// Default keybindings — comprehensive port of neomage/src/keybindings/defaultBindings.ts.
// All standard keyboard shortcuts for the application, organized by context.
// Includes platform-specific bindings and feature-gated shortcuts.

import 'package:neomage/core/platform/neomage_io.dart' show Platform;

import 'keybinding_types.dart';
import 'keybinding_resolver.dart';

// ════════════════════════════════════════════════════════════════════════════
// Platform detection helpers
// ════════════════════════════════════════════════════════════════════════════

/// Current platform string for shortcut selection.
String _getPlatform() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  return 'linux';
}

/// Platform-specific image paste shortcut:
/// - Windows: alt+v (ctrl+v is system paste)
/// - Other platforms: ctrl+v
String get _imagePasteKey => _getPlatform() == 'windows' ? 'alt+v' : 'ctrl+v';

/// Platform-specific mode cycle shortcut:
/// - Windows without VT mode: meta+m (shift+tab not reliable)
/// - Other platforms: shift+tab
String get _modeCycleKey {
  // On modern terminals shift+tab works, fallback for older Windows terminals.
  if (_getPlatform() == 'windows') return 'meta+m';
  return 'shift+tab';
}

// ════════════════════════════════════════════════════════════════════════════
// All valid keybinding action identifiers
// ════════════════════════════════════════════════════════════════════════════

/// Complete list of all known keybinding actions.
const List<String> allKeybindingActions = [
  // App-level actions (Global context)
  'app:interrupt',
  'app:exit',
  'app:toggleTodos',
  'app:toggleTranscript',
  'app:toggleBrief',
  'app:toggleTeammatePreview',
  'app:toggleTerminal',
  'app:redraw',
  'app:globalSearch',
  'app:quickOpen',
  // History navigation
  'history:search',
  'history:previous',
  'history:next',
  // Chat input actions
  'chat:cancel',
  'chat:killAgents',
  'chat:cycleMode',
  'chat:modelPicker',
  'chat:fastMode',
  'chat:thinkingToggle',
  'chat:submit',
  'chat:newline',
  'chat:undo',
  'chat:externalEditor',
  'chat:stash',
  'chat:imagePaste',
  'chat:messageActions',
  // Autocomplete menu actions
  'autocomplete:accept',
  'autocomplete:dismiss',
  'autocomplete:previous',
  'autocomplete:next',
  // Confirmation dialog actions
  'confirm:yes',
  'confirm:no',
  'confirm:previous',
  'confirm:next',
  'confirm:nextField',
  'confirm:previousField',
  'confirm:cycleMode',
  'confirm:toggle',
  'confirm:toggleExplanation',
  // Tabs navigation actions
  'tabs:next',
  'tabs:previous',
  // Transcript viewer actions
  'transcript:toggleShowAll',
  'transcript:exit',
  // History search actions
  'historySearch:next',
  'historySearch:accept',
  'historySearch:cancel',
  'historySearch:execute',
  // Task/agent actions
  'task:background',
  // Theme picker actions
  'theme:toggleSyntaxHighlighting',
  // Help menu actions
  'help:dismiss',
  // Attachment navigation
  'attachments:next',
  'attachments:previous',
  'attachments:remove',
  'attachments:exit',
  // Footer indicator actions
  'footer:up',
  'footer:down',
  'footer:next',
  'footer:previous',
  'footer:openSelected',
  'footer:clearSelection',
  'footer:close',
  // Message selector (rewind) actions
  'messageSelector:up',
  'messageSelector:down',
  'messageSelector:top',
  'messageSelector:bottom',
  'messageSelector:select',
  // Diff dialog actions
  'diff:dismiss',
  'diff:previousSource',
  'diff:nextSource',
  'diff:back',
  'diff:viewDetails',
  'diff:previousFile',
  'diff:nextFile',
  // Model picker actions
  'modelPicker:decreaseEffort',
  'modelPicker:increaseEffort',
  // Select component actions
  'select:next',
  'select:previous',
  'select:accept',
  'select:cancel',
  // Plugin dialog actions
  'plugin:toggle',
  'plugin:install',
  // Permission dialog actions
  'permission:toggleDebug',
  // Settings config panel actions
  'settings:search',
  'settings:retry',
  'settings:close',
  // Scroll actions
  'scroll:pageUp',
  'scroll:pageDown',
  'scroll:lineUp',
  'scroll:lineDown',
  'scroll:top',
  'scroll:bottom',
  // Selection actions
  'selection:copy',
  // Voice actions
  'voice:pushToTalk',
  // Message actions
  'messageActions:prev',
  'messageActions:next',
  'messageActions:top',
  'messageActions:bottom',
  'messageActions:prevUser',
  'messageActions:nextUser',
  'messageActions:escape',
  'messageActions:ctrlc',
  'messageActions:enter',
  'messageActions:c',
  'messageActions:p',
];

// ════════════════════════════════════════════════════════════════════════════
// Default binding blocks (JSON/config format)
// ════════════════════════════════════════════════════════════════════════════

/// Returns the default keybinding blocks in config format.
/// These are loaded first, then user keybindings.json overrides them.
List<KeybindingBlock> getDefaultBindingBlocks() => [
  // ── Global ──
  const KeybindingBlock(
    context: 'Global',
    bindings: {
      // ctrl+c and ctrl+d use special time-based double-press handling.
      // They ARE defined here so the resolver can find them, but they
      // CANNOT be rebound by users.
      'ctrl+c': 'app:interrupt',
      'ctrl+d': 'app:exit',
      'ctrl+l': 'app:redraw',
      'ctrl+t': 'app:toggleTodos',
      'ctrl+o': 'app:toggleTranscript',
      'ctrl+shift+o': 'app:toggleTeammatePreview',
      'ctrl+r': 'history:search',
      'ctrl+shift+f': 'app:globalSearch',
      'cmd+shift+f': 'app:globalSearch',
      'ctrl+shift+p': 'app:quickOpen',
      'cmd+shift+p': 'app:quickOpen',
    },
  ),

  // ── Chat ──
  KeybindingBlock(
    context: 'Chat',
    bindings: {
      'escape': 'chat:cancel',
      // ctrl+x chord prefix avoids shadowing readline editing keys.
      'ctrl+x ctrl+k': 'chat:killAgents',
      _modeCycleKey: 'chat:cycleMode',
      'meta+p': 'chat:modelPicker',
      'meta+o': 'chat:fastMode',
      'meta+t': 'chat:thinkingToggle',
      'enter': 'chat:submit',
      'up': 'history:previous',
      'down': 'history:next',
      // Undo has two bindings:
      // - ctrl+_ for legacy terminals (send \x1f control char)
      // - ctrl+shift+- for Kitty protocol
      'ctrl+_': 'chat:undo',
      'ctrl+shift+-': 'chat:undo',
      // External editor bindings
      'ctrl+x ctrl+e': 'chat:externalEditor',
      'ctrl+g': 'chat:externalEditor',
      'ctrl+s': 'chat:stash',
      // Image paste shortcut (platform-specific)
      _imagePasteKey: 'chat:imagePaste',
      'shift+up': 'chat:messageActions',
    },
  ),

  // ── Autocomplete ──
  const KeybindingBlock(
    context: 'Autocomplete',
    bindings: {
      'tab': 'autocomplete:accept',
      'escape': 'autocomplete:dismiss',
      'up': 'autocomplete:previous',
      'down': 'autocomplete:next',
    },
  ),

  // ── Settings ──
  const KeybindingBlock(
    context: 'Settings',
    bindings: {
      'escape': 'confirm:no',
      'up': 'select:previous',
      'down': 'select:next',
      'k': 'select:previous',
      'j': 'select:next',
      'ctrl+p': 'select:previous',
      'ctrl+n': 'select:next',
      'space': 'select:accept',
      'enter': 'settings:close',
      '/': 'settings:search',
      'r': 'settings:retry',
    },
  ),

  // ── Confirmation / Permission Dialog ──
  const KeybindingBlock(
    context: 'Confirmation',
    bindings: {
      'y': 'confirm:yes',
      'n': 'confirm:no',
      'enter': 'confirm:yes',
      'escape': 'confirm:no',
      'up': 'confirm:previous',
      'down': 'confirm:next',
      'tab': 'confirm:nextField',
      'space': 'confirm:toggle',
      'shift+tab': 'confirm:cycleMode',
      'ctrl+e': 'confirm:toggleExplanation',
      'ctrl+d': 'permission:toggleDebug',
    },
  ),

  // ── Tabs ──
  const KeybindingBlock(
    context: 'Tabs',
    bindings: {
      'tab': 'tabs:next',
      'shift+tab': 'tabs:previous',
      'right': 'tabs:next',
      'left': 'tabs:previous',
    },
  ),

  // ── Transcript ──
  const KeybindingBlock(
    context: 'Transcript',
    bindings: {
      'ctrl+e': 'transcript:toggleShowAll',
      'ctrl+c': 'transcript:exit',
      'escape': 'transcript:exit',
      'q': 'transcript:exit',
    },
  ),

  // ── History Search ──
  const KeybindingBlock(
    context: 'HistorySearch',
    bindings: {
      'ctrl+r': 'historySearch:next',
      'escape': 'historySearch:accept',
      'tab': 'historySearch:accept',
      'ctrl+c': 'historySearch:cancel',
      'enter': 'historySearch:execute',
    },
  ),

  // ── Task ──
  const KeybindingBlock(
    context: 'Task',
    bindings: {'ctrl+b': 'task:background'},
  ),

  // ── Theme Picker ──
  const KeybindingBlock(
    context: 'ThemePicker',
    bindings: {'ctrl+t': 'theme:toggleSyntaxHighlighting'},
  ),

  // ── Scroll ──
  const KeybindingBlock(
    context: 'Scroll',
    bindings: {
      'pageup': 'scroll:pageUp',
      'pagedown': 'scroll:pageDown',
      'wheelup': 'scroll:lineUp',
      'wheeldown': 'scroll:lineDown',
      'ctrl+home': 'scroll:top',
      'ctrl+end': 'scroll:bottom',
      'ctrl+shift+c': 'selection:copy',
      'cmd+c': 'selection:copy',
    },
  ),

  // ── Help ──
  const KeybindingBlock(context: 'Help', bindings: {'escape': 'help:dismiss'}),

  // ── Attachments ──
  const KeybindingBlock(
    context: 'Attachments',
    bindings: {
      'right': 'attachments:next',
      'left': 'attachments:previous',
      'backspace': 'attachments:remove',
      'delete': 'attachments:remove',
      'down': 'attachments:exit',
      'escape': 'attachments:exit',
    },
  ),

  // ── Footer ──
  const KeybindingBlock(
    context: 'Footer',
    bindings: {
      'up': 'footer:up',
      'ctrl+p': 'footer:up',
      'down': 'footer:down',
      'ctrl+n': 'footer:down',
      'right': 'footer:next',
      'left': 'footer:previous',
      'enter': 'footer:openSelected',
      'escape': 'footer:clearSelection',
    },
  ),

  // ── Message Selector (rewind dialog) ──
  const KeybindingBlock(
    context: 'MessageSelector',
    bindings: {
      'up': 'messageSelector:up',
      'down': 'messageSelector:down',
      'k': 'messageSelector:up',
      'j': 'messageSelector:down',
      'ctrl+p': 'messageSelector:up',
      'ctrl+n': 'messageSelector:down',
      'ctrl+up': 'messageSelector:top',
      'shift+up': 'messageSelector:top',
      'meta+up': 'messageSelector:top',
      'shift+k': 'messageSelector:top',
      'ctrl+down': 'messageSelector:bottom',
      'shift+down': 'messageSelector:bottom',
      'meta+down': 'messageSelector:bottom',
      'shift+j': 'messageSelector:bottom',
      'enter': 'messageSelector:select',
    },
  ),

  // ── Message Actions ──
  const KeybindingBlock(
    context: 'MessageActions',
    bindings: {
      'up': 'messageActions:prev',
      'down': 'messageActions:next',
      'k': 'messageActions:prev',
      'j': 'messageActions:next',
      'meta+up': 'messageActions:top',
      'meta+down': 'messageActions:bottom',
      'super+up': 'messageActions:top',
      'super+down': 'messageActions:bottom',
      'shift+up': 'messageActions:prevUser',
      'shift+down': 'messageActions:nextUser',
      'escape': 'messageActions:escape',
      'ctrl+c': 'messageActions:ctrlc',
      'enter': 'messageActions:enter',
      'c': 'messageActions:c',
      'p': 'messageActions:p',
    },
  ),

  // ── Diff Dialog ──
  const KeybindingBlock(
    context: 'DiffDialog',
    bindings: {
      'escape': 'diff:dismiss',
      'left': 'diff:previousSource',
      'right': 'diff:nextSource',
      'up': 'diff:previousFile',
      'down': 'diff:nextFile',
      'enter': 'diff:viewDetails',
    },
  ),

  // ── Model Picker ──
  const KeybindingBlock(
    context: 'ModelPicker',
    bindings: {
      'left': 'modelPicker:decreaseEffort',
      'right': 'modelPicker:increaseEffort',
    },
  ),

  // ── Select (used by /model, /resume, permission prompts, etc.) ──
  const KeybindingBlock(
    context: 'Select',
    bindings: {
      'up': 'select:previous',
      'down': 'select:next',
      'j': 'select:next',
      'k': 'select:previous',
      'ctrl+n': 'select:next',
      'ctrl+p': 'select:previous',
      'enter': 'select:accept',
      'escape': 'select:cancel',
    },
  ),

  // ── Plugin ──
  const KeybindingBlock(
    context: 'Plugin',
    bindings: {'space': 'plugin:toggle', 'i': 'plugin:install'},
  ),
];

// ════════════════════════════════════════════════════════════════════════════
// Flat parsed binding list
// ════════════════════════════════════════════════════════════════════════════

/// Returns the default bindings as a flat list of ParsedBindings.
List<ParsedBinding> getDefaultBindings() =>
    parseBindingBlocks(getDefaultBindingBlocks());

// ════════════════════════════════════════════════════════════════════════════
// Convenience helpers for building individual bindings
// ════════════════════════════════════════════════════════════════════════════

/// Create a single-keystroke ParsedBinding.
ParsedBinding bind(String keys, String action, KeybindingContext context) {
  return ParsedBinding(
    chord: [parseKeystroke(keys)],
    action: action,
    context: context,
  );
}

/// Create a chord (multi-keystroke) ParsedBinding.
ParsedBinding chord(String keys, String action, KeybindingContext context) {
  return ParsedBinding(
    chord: parseChord(keys),
    action: action,
    context: context,
  );
}

/// Create an unbinding (null action) ParsedBinding.
ParsedBinding unbind(String keys, KeybindingContext context) {
  return ParsedBinding(chord: parseChord(keys), action: null, context: context);
}
