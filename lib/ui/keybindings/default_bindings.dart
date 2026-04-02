// Default keybindings — port of openclaude/src/keybindings/defaultBindings.ts.
// Standard keyboard shortcuts for the application.

import 'keybinding_types.dart';

/// Default keybindings for the application.
List<ParsedBinding> getDefaultBindings() => [
      // ── Global ──
      _bind('ctrl+c', 'interrupt', KeybindingContext.global),
      _bind('ctrl+d', 'exit', KeybindingContext.global),
      _bind('ctrl+l', 'clear_screen', KeybindingContext.global),
      _bind('ctrl+p', 'command_palette', KeybindingContext.global),
      _bind('ctrl+shift+p', 'command_palette', KeybindingContext.global),
      _bind('ctrl+,', 'settings', KeybindingContext.global),

      // ── Chat ──
      _bind('enter', 'submit', KeybindingContext.chat),
      _bind('shift+enter', 'newline', KeybindingContext.chat),
      _bind('escape', 'cancel', KeybindingContext.chat),
      _bind('up', 'history_prev', KeybindingContext.chat),
      _bind('down', 'history_next', KeybindingContext.chat),
      _bind('ctrl+r', 'search_history', KeybindingContext.chat),
      _bind('ctrl+z', 'undo', KeybindingContext.chat),
      _bind('ctrl+shift+z', 'redo', KeybindingContext.chat),

      // ── Input ──
      _bind('tab', 'accept_autocomplete', KeybindingContext.input),
      _bind('escape', 'dismiss_autocomplete', KeybindingContext.input),
      _bind('ctrl+space', 'trigger_autocomplete', KeybindingContext.input),
      _bind('ctrl+a', 'select_all', KeybindingContext.input),
      _bind('ctrl+backspace', 'delete_word', KeybindingContext.input),

      // ── Autocomplete ──
      _bind('up', 'prev_suggestion', KeybindingContext.autocomplete),
      _bind('down', 'next_suggestion', KeybindingContext.autocomplete),
      _bind('enter', 'accept_suggestion', KeybindingContext.autocomplete),
      _bind('tab', 'accept_suggestion', KeybindingContext.autocomplete),
      _bind('escape', 'dismiss', KeybindingContext.autocomplete),

      // ── Permission Dialog ──
      _bind('y', 'allow_once', KeybindingContext.permissionDialog),
      _bind('a', 'allow_always', KeybindingContext.permissionDialog),
      _bind('n', 'deny', KeybindingContext.permissionDialog),
      _bind('escape', 'deny', KeybindingContext.permissionDialog),

      // ── Command Palette ──
      _bind('up', 'prev_item', KeybindingContext.commandPalette),
      _bind('down', 'next_item', KeybindingContext.commandPalette),
      _bind('enter', 'select_item', KeybindingContext.commandPalette),
      _bind('escape', 'dismiss', KeybindingContext.commandPalette),

      // ── Diff View ──
      _bind('j', 'next_hunk', KeybindingContext.diffView),
      _bind('k', 'prev_hunk', KeybindingContext.diffView),
      _bind('y', 'accept_change', KeybindingContext.diffView),
      _bind('n', 'reject_change', KeybindingContext.diffView),
      _bind('q', 'close', KeybindingContext.diffView),

      // ── Plan Mode ──
      _bind('escape', 'exit_plan', KeybindingContext.planMode),
      _bind('enter', 'confirm_plan', KeybindingContext.planMode),

      // ── Chord bindings (Ctrl+K prefix) ──
      _chord('ctrl+k ctrl+s', 'save', KeybindingContext.global),
      _chord('ctrl+k ctrl+c', 'toggle_compact', KeybindingContext.chat),
      _chord('ctrl+k ctrl+t', 'toggle_thinking', KeybindingContext.chat),
      _chord('ctrl+k ctrl+m', 'switch_model', KeybindingContext.chat),
      _chord('ctrl+k ctrl+d', 'toggle_diff', KeybindingContext.chat),
    ];

ParsedBinding _bind(String keys, String action, KeybindingContext context) {
  return ParsedBinding(
    chord: [parseKeystroke(keys)],
    action: action,
    context: context,
  );
}

ParsedBinding _chord(String keys, String action, KeybindingContext context) {
  return ParsedBinding(
    chord: parseChord(keys),
    action: action,
    context: context,
  );
}
