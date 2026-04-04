// Command registry — expanded port of NeomClaw's command dispatch system.
// Manages command registration, lookup (by name or alias), execution,
// completions, help, and built-in command scaffolding.

import 'dart:async';

import 'command.dart';
import '../tools/tool.dart';

// ─── CommandCategory ─────────────────────────────────────────────────────────

/// Logical category for grouping commands in help output and completions.
enum CommandCategory {
  /// Navigation commands (cd, open, etc.).
  navigation,

  /// Session management (clear, compact, logout, etc.).
  session,

  /// Configuration commands (config, model, permissions, etc.).
  config,

  /// Tool-related commands (tools, allowed-tools, etc.).
  tools,

  /// Git commands (commit, pr-comments, review, etc.).
  git,

  /// Debugging commands (debug, doctor, cost, etc.).
  debug,

  /// System commands (init, update-cli, etc.).
  system,

  /// Help and documentation.
  help,
}

// ─── CommandRegistration ─────────────────────────────────────────────────────

/// Wraps a [Command] with registry metadata.
class CommandRegistration {
  /// The underlying command instance.
  final Command command;

  /// Logical category.
  final CommandCategory category;

  /// Additional aliases beyond what the command itself declares.
  final List<String> extraAliases;

  /// Whether this command is hidden from help output.
  final bool hidden;

  /// Whether this command requires authentication.
  final bool requiresAuth;

  /// Whether this command requires a git repository context.
  final bool requiresGit;

  /// Number of times this command has been executed.
  int executionCount;

  /// Timestamp of last execution.
  DateTime? lastExecutedAt;

  CommandRegistration({
    required this.command,
    required this.category,
    this.extraAliases = const [],
    this.hidden = false,
    this.requiresAuth = false,
    this.requiresGit = false,
    this.executionCount = 0,
    this.lastExecutedAt,
  });

  /// Command name.
  String get name => command.name;

  /// All aliases (command-defined + extra).
  List<String> get allAliases => [...command.aliases, ...extraAliases];

  /// Whether this command should appear in help/completions.
  bool get isVisible => command.isEnabled && !hidden && !command.isHidden;
}

// ─── CommandExecutionEvent ───────────────────────────────────────────────────

/// Event emitted after a command execution.
class CommandExecutionEvent {
  final String commandName;
  final CommandCategory category;
  final String args;
  final bool isError;
  final DateTime timestamp;

  const CommandExecutionEvent({
    required this.commandName,
    required this.category,
    required this.args,
    required this.isError,
    required this.timestamp,
  });
}

// ─── CommandRegistry ─────────────────────────────────────────────────────────

/// Full-featured command registry.
///
/// Manages command registration/unregistration, lookup by name or alias,
/// execution dispatching, tab-completions, help generation, and stats.
class CommandRegistry {
  final List<CommandRegistration> _commands = [];
  final Map<String, CommandRegistration> _byName = {};
  final Map<String, CommandRegistration> _byAlias = {};

  /// Stream controller for command execution events.
  final _executionController =
      StreamController<CommandExecutionEvent>.broadcast();

  /// Stream of command execution events.
  Stream<CommandExecutionEvent> get onCommandExecuted =>
      _executionController.stream;

  // ── Registration ─────────────────────────────────────────────────────────

  /// Register a command with metadata.
  void register(
    Command command, {
    CommandCategory category = CommandCategory.system,
    List<String> extraAliases = const [],
    bool hidden = false,
    bool requiresAuth = false,
    bool requiresGit = false,
  }) {
    final reg = CommandRegistration(
      command: command,
      category: category,
      extraAliases: extraAliases,
      hidden: hidden,
      requiresAuth: requiresAuth,
      requiresGit: requiresGit,
    );
    _commands.add(reg);
    _byName[command.name] = reg;
    for (final alias in reg.allAliases) {
      _byAlias[alias] = reg;
    }
  }

  /// Register multiple commands with the same category.
  void registerAll(
    Iterable<Command> commands, {
    CommandCategory category = CommandCategory.system,
  }) {
    for (final cmd in commands) {
      register(cmd, category: category);
    }
  }

  /// Unregister a command by name.
  void unregister(String name) {
    final reg = _byName.remove(name);
    if (reg != null) {
      _commands.remove(reg);
      for (final alias in reg.allAliases) {
        _byAlias.remove(alias);
      }
    }
  }

  // ── Lookup ───────────────────────────────────────────────────────────────

  /// Find a command by name or alias. Strips leading `/`.
  CommandRegistration? get(String name) {
    final normalized = name.startsWith('/') ? name.substring(1) : name;
    return _byName[normalized] ?? _byAlias[normalized];
  }

  /// Get the underlying Command by name or alias.
  Command? getCommand(String name) => get(name)?.command;

  /// Check if a command exists.
  bool isValid(String name) => get(name) != null;

  /// All registrations.
  List<CommandRegistration> get getAll => List.unmodifiable(_commands);

  /// All enabled, non-hidden commands (for help/typeahead).
  List<CommandRegistration> get visible =>
      _commands.where((r) => r.isVisible).toList();

  /// Get all commands in a specific category.
  List<CommandRegistration> getByCategory(CommandCategory category) =>
      _commands.where((r) => r.category == category).toList();

  /// Get aliases for a command.
  List<String> getAliases(String name) {
    final reg = get(name);
    return reg?.allAliases ?? [];
  }

  // ── Execution ────────────────────────────────────────────────────────────

  /// Execute a command by name with the given args and context.
  ///
  /// Returns `null` if the command is not found or not a local command.
  Future<CommandResult?> execute(
    String name,
    String args,
    ToolUseContext context,
  ) async {
    final reg = get(name);
    if (reg == null) return null;

    if (!reg.command.isEnabled) {
      return TextCommandResult('Command "/$name" is currently disabled.');
    }

    if (reg.requiresAuth) {
      // Caller should check auth before executing; this is a fallback.
    }

    CommandResult? result;
    bool isError = false;

    try {
      if (reg.command is LocalCommand) {
        result = await (reg.command as LocalCommand).execute(args, context);
      } else if (reg.command is LocalUiCommand) {
        result = await (reg.command as LocalUiCommand).execute(args, context);
      } else {
        // Prompt commands are handled by the conversation loop, not here.
        return null;
      }
    } catch (e) {
      isError = true;
      result = TextCommandResult('Error: $e');
    }

    // Track stats.
    reg.executionCount++;
    reg.lastExecutedAt = DateTime.now();

    // Emit event.
    _executionController.add(CommandExecutionEvent(
      commandName: reg.name,
      category: reg.category,
      args: args,
      isError: isError,
      timestamp: DateTime.now(),
    ));

    return result;
  }

  // ── Completions ──────────────────────────────────────────────────────────

  /// Get tab-completion candidates for a prefix.
  ///
  /// Matches command names and aliases that start with [prefix].
  /// Returns sorted, unique results.
  List<String> getCompletions(String prefix) {
    final p = prefix.toLowerCase();
    final results = <String>{};

    for (final reg in _commands) {
      if (!reg.isVisible) continue;
      if (reg.name.toLowerCase().startsWith(p)) {
        results.add(reg.name);
      }
      for (final alias in reg.allAliases) {
        if (alias.toLowerCase().startsWith(p)) {
          results.add(alias);
        }
      }
    }

    return results.toList()..sort();
  }

  /// Search for commands matching a prefix (for typeahead).
  List<CommandRegistration> search(String prefix) {
    final p = prefix.toLowerCase();
    return visible.where((r) {
      if (r.name.toLowerCase().startsWith(p)) return true;
      return r.allAliases.any((a) => a.toLowerCase().startsWith(p));
    }).toList();
  }

  // ── Help ─────────────────────────────────────────────────────────────────

  /// Get help text for a single command.
  String? getHelp(String name) {
    final reg = get(name);
    if (reg == null) return null;

    final buf = StringBuffer();
    buf.writeln('/${reg.name} — ${reg.command.description}');

    if (reg.allAliases.isNotEmpty) {
      buf.writeln('  Aliases: ${reg.allAliases.map((a) => "/$a").join(", ")}');
    }
    if (reg.command.argumentHint != null) {
      buf.writeln('  Usage: /${reg.name} ${reg.command.argumentHint}');
    }

    buf.writeln('  Category: ${reg.category.name}');
    buf.writeln('  Type: ${reg.command.type.name}');

    if (reg.requiresAuth) buf.writeln('  Requires authentication');
    if (reg.requiresGit) buf.writeln('  Requires git repository');

    return buf.toString();
  }

  /// Get help for all visible commands, grouped by category.
  String getAllHelp() {
    final buf = StringBuffer();
    buf.writeln('Available commands:\n');

    final byCategory = <CommandCategory, List<CommandRegistration>>{};
    for (final reg in visible) {
      byCategory.putIfAbsent(reg.category, () => []).add(reg);
    }

    for (final category in CommandCategory.values) {
      final cmds = byCategory[category];
      if (cmds == null || cmds.isEmpty) continue;

      buf.writeln('${_categoryLabel(category)}:');
      for (final reg in cmds) {
        final aliases = reg.allAliases.isNotEmpty
            ? ' (${reg.allAliases.map((a) => "/$a").join(", ")})'
            : '';
        buf.writeln('  /${reg.name}$aliases — ${reg.command.description}');
      }
      buf.writeln();
    }

    return buf.toString();
  }

  static String _categoryLabel(CommandCategory cat) => switch (cat) {
        CommandCategory.navigation => 'Navigation',
        CommandCategory.session => 'Session',
        CommandCategory.config => 'Configuration',
        CommandCategory.tools => 'Tools',
        CommandCategory.git => 'Git',
        CommandCategory.debug => 'Debug',
        CommandCategory.system => 'System',
        CommandCategory.help => 'Help',
      };

  // ── Builtin Registration ─────────────────────────────────────────────────

  /// Register all built-in commands.
  ///
  /// Accepts maps of command instances grouped by category. Each entry
  /// is a command instance; the registry assigns the correct category,
  /// aliases, and flags.
  ///
  /// Call this during app initialization with all 88 built-in commands.
  void registerBuiltinCommands({
    List<Command> navigationCommands = const [],
    List<Command> sessionCommands = const [],
    List<Command> configCommands = const [],
    List<Command> toolCommands = const [],
    List<Command> gitCommands = const [],
    List<Command> debugCommands = const [],
    List<Command> systemCommands = const [],
    List<Command> helpCommands = const [],
  }) {
    for (final cmd in navigationCommands) {
      register(cmd, category: CommandCategory.navigation);
    }
    for (final cmd in sessionCommands) {
      register(cmd, category: CommandCategory.session);
    }
    for (final cmd in configCommands) {
      register(cmd, category: CommandCategory.config);
    }
    for (final cmd in toolCommands) {
      register(cmd, category: CommandCategory.tools);
    }
    for (final cmd in gitCommands) {
      register(cmd, category: CommandCategory.git, requiresGit: true);
    }
    for (final cmd in debugCommands) {
      register(cmd, category: CommandCategory.debug);
    }
    for (final cmd in systemCommands) {
      register(cmd, category: CommandCategory.system);
    }
    for (final cmd in helpCommands) {
      register(cmd, category: CommandCategory.help);
    }
  }

  /// Register extended / plugin commands discovered at runtime.
  ///
  /// These are typically loaded from skills, MCP servers, or user plugins.
  void registerExtendedCommands(
    List<Command> commands, {
    CommandCategory category = CommandCategory.system,
    bool hidden = false,
  }) {
    for (final cmd in commands) {
      register(cmd, category: category, hidden: hidden);
    }
  }

  // ── Cleanup ──────────────────────────────────────────────────────────────

  /// Clear all commands.
  void clear() {
    _commands.clear();
    _byName.clear();
    _byAlias.clear();
  }

  /// Dispose of internal resources.
  void dispose() {
    _executionController.close();
  }
}
