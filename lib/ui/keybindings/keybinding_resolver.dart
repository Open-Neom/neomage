// Keybinding resolver — port of openclaude/src/keybindings/resolver.ts.
// Stateful chord resolution with binding priority.

import 'keybinding_types.dart';

/// Reserved keys that cannot be rebound.
const reservedKeys = {'ctrl+c', 'ctrl+d'};

/// Keybinding resolver — resolves keystrokes to actions with chord support.
class KeybindingResolver {
  final List<ParsedBinding> _bindings = [];
  List<ParsedKeystroke>? _pendingChord;

  /// Register bindings (later registrations take priority).
  void registerBindings(List<ParsedBinding> bindings) {
    _bindings.addAll(bindings);
  }

  /// Clear all bindings.
  void clearBindings() {
    _bindings.clear();
    _pendingChord = null;
  }

  /// Whether a chord is in progress.
  bool get isChordPending => _pendingChord != null;

  /// Cancel any pending chord.
  void cancelChord() {
    _pendingChord = null;
  }

  /// Resolve a keystroke in the given context.
  ResolveResult resolve(
    ParsedKeystroke keystroke,
    KeybindingContext context,
  ) {
    // Escape cancels chord
    if (keystroke.key == 'escape' && _pendingChord != null) {
      _pendingChord = null;
      return const ChordCancelledResult();
    }

    // If chord in progress, try to complete it
    if (_pendingChord != null) {
      return _resolveChord(keystroke, context);
    }

    // Single-keystroke resolution
    return _resolveSingle(keystroke, context);
  }

  /// Get display text for an action in a context.
  String? getBindingDisplayText(String action, KeybindingContext context) {
    for (final binding in _bindings.reversed) {
      if (binding.action == action &&
          (binding.context == context ||
              binding.context == KeybindingContext.global)) {
        return binding.chord
            .map((k) => k.toDisplayString())
            .join(' ');
      }
    }
    return null;
  }

  /// Get all bindings for a context.
  List<ParsedBinding> getBindingsForContext(KeybindingContext context) {
    return _bindings
        .where(
          (b) =>
              b.context == context || b.context == KeybindingContext.global,
        )
        .toList();
  }

  // ── Private ──

  ResolveResult _resolveSingle(
    ParsedKeystroke keystroke,
    KeybindingContext context,
  ) {
    // Check for chord prefix (multi-keystroke binding starts)
    for (final binding in _bindings.reversed) {
      if (binding.chord.length > 1 &&
          (binding.context == context ||
              binding.context == KeybindingContext.global)) {
        if (keystrokesEqual(binding.chord.first, keystroke)) {
          _pendingChord = [keystroke];
          return ChordStartedResult(_pendingChord!);
        }
      }
    }

    // Single-keystroke match (last registered wins)
    for (final binding in _bindings.reversed) {
      if (binding.chord.length == 1 &&
          (binding.context == context ||
              binding.context == KeybindingContext.global)) {
        if (keystrokesEqual(binding.chord.first, keystroke)) {
          if (binding.action == null) return const UnboundResult();
          return MatchResult(binding.action!);
        }
      }
    }

    return const NoMatchResult();
  }

  ResolveResult _resolveChord(
    ParsedKeystroke keystroke,
    KeybindingContext context,
  ) {
    final pending = [..._pendingChord!, keystroke];

    // Check for exact match
    for (final binding in _bindings.reversed) {
      if (binding.chord.length == pending.length &&
          (binding.context == context ||
              binding.context == KeybindingContext.global)) {
        var matches = true;
        for (var i = 0; i < pending.length; i++) {
          if (!keystrokesEqual(binding.chord[i], pending[i])) {
            matches = false;
            break;
          }
        }
        if (matches) {
          _pendingChord = null;
          if (binding.action == null) return const UnboundResult();
          return MatchResult(binding.action!);
        }
      }
    }

    // Check for prefix (longer chord in progress)
    for (final binding in _bindings.reversed) {
      if (binding.chord.length > pending.length &&
          (binding.context == context ||
              binding.context == KeybindingContext.global)) {
        var prefixMatches = true;
        for (var i = 0; i < pending.length; i++) {
          if (!keystrokesEqual(binding.chord[i], pending[i])) {
            prefixMatches = false;
            break;
          }
        }
        if (prefixMatches) {
          _pendingChord = pending;
          return ChordStartedResult(pending);
        }
      }
    }

    // No match — cancel chord
    _pendingChord = null;
    return const ChordCancelledResult();
  }
}
