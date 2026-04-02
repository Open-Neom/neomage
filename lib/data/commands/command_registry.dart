// Command registry — port of openclaude/src/commands.ts registry/dispatch.
// Manages command registration, lookup, and filtering.

import 'command.dart';

/// Registry for all available commands.
class CommandRegistry {
  final List<Command> _commands = [];
  final Map<String, Command> _byName = {};
  final Map<String, Command> _byAlias = {};

  /// Register a command.
  void register(Command command) {
    _commands.add(command);
    _byName[command.name] = command;
    for (final alias in command.aliases) {
      _byAlias[alias] = command;
    }
  }

  /// Register multiple commands.
  void registerAll(Iterable<Command> commands) {
    for (final cmd in commands) {
      register(cmd);
    }
  }

  /// Find a command by name or alias. Returns null if not found.
  Command? find(String name) {
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    return _byName[normalized] ?? _byAlias[normalized];
  }

  /// Check if a command exists.
  bool has(String name) => find(name) != null;

  /// All registered commands.
  List<Command> get all => List.unmodifiable(_commands);

  /// All enabled, non-hidden commands (for help/typeahead).
  List<Command> get visible =>
      _commands.where((c) => c.isEnabled && !c.isHidden).toList();

  /// Filter commands matching a prefix (for typeahead).
  List<Command> search(String prefix) {
    final p = prefix.toLowerCase();
    return visible.where((c) {
      if (c.name.toLowerCase().startsWith(p)) return true;
      return c.aliases.any((a) => a.toLowerCase().startsWith(p));
    }).toList();
  }

  /// Get all commands of a specific type.
  List<Command> byType(CommandType type) =>
      _commands.where((c) => c.type == type && c.isEnabled).toList();

  /// Unregister a command by name.
  void unregister(String name) {
    final cmd = _byName.remove(name);
    if (cmd != null) {
      _commands.remove(cmd);
      for (final alias in cmd.aliases) {
        _byAlias.remove(alias);
      }
    }
  }

  /// Clear all commands.
  void clear() {
    _commands.clear();
    _byName.clear();
    _byAlias.clear();
  }
}
