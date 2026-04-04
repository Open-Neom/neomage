// Extended commands — port of remaining NeomClaw commands.
// All commands not already ported as individual files are collected here.

import 'package:neom_claw/core/platform/claw_io.dart';

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

// ════════════════════════════════════════════════════════════════════════════
// Navigation & Context
// ════════════════════════════════════════════════════════════════════════════

/// /add-dir — add additional working directories to the session.
class AddDirCommand extends LocalCommand {
  final List<String> _extraDirs = [];

  List<String> get extraDirs => List.unmodifiable(_extraDirs);

  @override
  String get name => 'add-dir';

  @override
  String get description => 'Add additional working directories to the session';

  @override
  String? get argumentHint => '<path> [<path> ...]';

  @override
  List<String> get aliases => const ['adddir'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    if (args.trim().isEmpty) {
      if (_extraDirs.isEmpty) {
        return const TextCommandResult(
          'No additional directories added.\n'
          'Usage: /add-dir <path> [<path> ...]',
        );
      }
      final buffer = StringBuffer();
      buffer.writeln('Additional working directories:');
      for (final dir in _extraDirs) {
        buffer.writeln('  $dir');
      }
      return TextCommandResult(buffer.toString());
    }

    final paths = args.trim().split(RegExp(r'\s+'));
    final added = <String>[];
    final errors = <String>[];

    for (final path in paths) {
      final resolved = _resolvePath(path, context.cwd);
      final dir = Directory(resolved);
      if (await dir.exists()) {
        if (!_extraDirs.contains(resolved)) {
          _extraDirs.add(resolved);
          added.add(resolved);
        } else {
          errors.add('$path — already added');
        }
      } else {
        errors.add('$path — directory not found');
      }
    }

    final buffer = StringBuffer();
    if (added.isNotEmpty) {
      buffer.writeln('Added ${added.length} director${added.length == 1 ? 'y' : 'ies'}:');
      for (final d in added) {
        buffer.writeln('  $d');
      }
    }
    if (errors.isNotEmpty) {
      if (added.isNotEmpty) buffer.writeln();
      buffer.writeln('Errors:');
      for (final e in errors) {
        buffer.writeln('  $e');
      }
    }
    return TextCommandResult(buffer.toString());
  }

  String _resolvePath(String path, String cwd) {
    if (path.startsWith('/')) return path;
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '/';
      return '$home/${path.substring(2)}';
    }
    return '$cwd/$path';
  }
}

/// /cd — change working directory.
class CdCommand extends LocalCommand {
  final void Function(String) onDirectoryChange;
  final String Function() getCurrentDir;

  CdCommand({
    required this.onDirectoryChange,
    required this.getCurrentDir,
  });

  @override
  String get name => 'cd';

  @override
  String get description => 'Change the working directory';

  @override
  String? get argumentHint => '<path>';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    if (args.trim().isEmpty) {
      return TextCommandResult('Current directory: ${getCurrentDir()}');
    }

    var target = args.trim();
    if (target.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '/';
      target = '$home/${target.substring(2)}';
    } else if (!target.startsWith('/')) {
      target = '${getCurrentDir()}/$target';
    }

    final dir = Directory(target);
    if (!await dir.exists()) {
      return TextCommandResult('Directory not found: $target');
    }

    final resolved = dir.resolveSymbolicLinksSync();
    onDirectoryChange(resolved);
    return TextCommandResult('Changed directory to: $resolved');
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Configuration
// ════════════════════════════════════════════════════════════════════════════

/// /config — view/edit settings.
class ConfigCommand extends LocalCommand {
  final Map<String, dynamic> Function() getConfig;
  final void Function(String key, dynamic value) setConfig;

  ConfigCommand({
    required this.getConfig,
    required this.setConfig,
  });

  @override
  String get name => 'config';

  @override
  String get description => 'View or modify configuration settings';

  @override
  String? get argumentHint => '[get <key>|set <key> <value>|list]';

  @override
  List<String> get aliases => const ['settings'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
        return _listConfig();
      case 'get':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /config get <key>');
        }
        return _getConfig(parts[1]);
      case 'set':
        if (parts.length < 3) {
          return const TextCommandResult('Usage: /config set <key> <value>');
        }
        return _setConfig(parts[1], parts.sublist(2).join(' '));
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /config [list|get <key>|set <key> <value>]',
        );
    }
  }

  CommandResult _listConfig() {
    final config = getConfig();
    if (config.isEmpty) {
      return const TextCommandResult('No configuration settings found.');
    }
    final buffer = StringBuffer();
    buffer.writeln('Configuration:');
    for (final entry in config.entries) {
      buffer.writeln('  ${entry.key} = ${entry.value}');
    }
    return TextCommandResult(buffer.toString());
  }

  CommandResult _getConfig(String key) {
    final config = getConfig();
    if (!config.containsKey(key)) {
      return TextCommandResult('Key not found: $key');
    }
    return TextCommandResult('$key = ${config[key]}');
  }

  CommandResult _setConfig(String key, String value) {
    // Parse value types
    dynamic parsed;
    if (value == 'true') {
      parsed = true;
    } else if (value == 'false') {
      parsed = false;
    } else if (int.tryParse(value) != null) {
      parsed = int.parse(value);
    } else if (double.tryParse(value) != null) {
      parsed = double.parse(value);
    } else {
      parsed = value;
    }

    setConfig(key, parsed);
    return TextCommandResult('Set $key = $parsed');
  }
}

/// /permissions — manage permission rules.
class PermissionsCommand extends LocalCommand {
  final Map<String, String> Function() getPermissions;
  final void Function(String tool, String rule) setPermission;

  PermissionsCommand({
    required this.getPermissions,
    required this.setPermission,
  });

  @override
  String get name => 'permissions';

  @override
  String get description => 'View and manage tool permission rules';

  @override
  String? get argumentHint => '[list|allow <tool>|deny <tool>|ask <tool>]';

  @override
  List<String> get aliases => const ['perms'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
        return _listPermissions();
      case 'allow':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /permissions allow <tool>');
        }
        setPermission(parts[1], 'allow');
        return TextCommandResult('Allowed: ${parts[1]}');
      case 'deny':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /permissions deny <tool>');
        }
        setPermission(parts[1], 'deny');
        return TextCommandResult('Denied: ${parts[1]}');
      case 'ask':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /permissions ask <tool>');
        }
        setPermission(parts[1], 'ask');
        return TextCommandResult('Set to ask: ${parts[1]}');
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /permissions [list|allow <tool>|deny <tool>|ask <tool>]',
        );
    }
  }

  CommandResult _listPermissions() {
    final perms = getPermissions();
    if (perms.isEmpty) {
      return const TextCommandResult(
        'No custom permission rules. Using defaults (ask for destructive tools).',
      );
    }
    final buffer = StringBuffer();
    buffer.writeln('Permission rules:');
    for (final entry in perms.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
    return TextCommandResult(buffer.toString());
  }
}

/// /hooks — manage lifecycle hooks.
class HooksCommand extends LocalCommand {
  final Map<String, List<String>> Function() getHooks;
  final void Function(String event, String command) addHook;
  final void Function(String event, int index) removeHook;

  HooksCommand({
    required this.getHooks,
    required this.addHook,
    required this.removeHook,
  });

  @override
  String get name => 'hooks';

  @override
  String get description => 'View and manage lifecycle hooks';

  @override
  String? get argumentHint => '[list|add <event> <cmd>|remove <event> <index>]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
        return _listHooks();
      case 'add':
        if (parts.length < 3) {
          return const TextCommandResult(
            'Usage: /hooks add <event> <command>\n'
            'Events: PreToolUse, PostToolUse, Notification, Stop',
          );
        }
        final event = parts[1];
        final command = parts.sublist(2).join(' ');
        addHook(event, command);
        return TextCommandResult('Added hook on $event: $command');
      case 'remove':
        if (parts.length < 3) {
          return const TextCommandResult(
            'Usage: /hooks remove <event> <index>',
          );
        }
        final event = parts[1];
        final index = int.tryParse(parts[2]);
        if (index == null) {
          return const TextCommandResult('Index must be a number.');
        }
        removeHook(event, index);
        return TextCommandResult('Removed hook #$index from $event.');
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /hooks [list|add <event> <cmd>|remove <event> <index>]',
        );
    }
  }

  CommandResult _listHooks() {
    final hooks = getHooks();
    if (hooks.isEmpty) {
      return const TextCommandResult('No hooks configured.');
    }
    final buffer = StringBuffer();
    buffer.writeln('Configured hooks:');
    for (final entry in hooks.entries) {
      buffer.writeln('  ${entry.key}:');
      for (var i = 0; i < entry.value.length; i++) {
        buffer.writeln('    [$i] ${entry.value[i]}');
      }
    }
    return TextCommandResult(buffer.toString());
  }
}

/// /theme — change color theme.
class ThemeCommand extends LocalCommand {
  static const _availableThemes = [
    'dark',
    'light',
    'solarized-dark',
    'solarized-light',
    'monokai',
    'dracula',
    'nord',
    'gruvbox',
  ];

  final String Function() getCurrentTheme;
  final void Function(String) setTheme;

  ThemeCommand({
    required this.getCurrentTheme,
    required this.setTheme,
  });

  @override
  String get name => 'theme';

  @override
  String get description => 'Change the color theme';

  @override
  String? get argumentHint => '[<theme-name>|list]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final arg = args.trim().toLowerCase();

    if (arg.isEmpty) {
      return TextCommandResult(
        'Current theme: ${getCurrentTheme()}\n'
        'Usage: /theme <name> or /theme list',
      );
    }

    if (arg == 'list') {
      final current = getCurrentTheme();
      final buffer = StringBuffer();
      buffer.writeln('Available themes:');
      for (final t in _availableThemes) {
        final marker = t == current ? ' (current)' : '';
        buffer.writeln('  $t$marker');
      }
      return TextCommandResult(buffer.toString());
    }

    if (!_availableThemes.contains(arg)) {
      return TextCommandResult(
        'Unknown theme: $arg\n'
        'Available: ${_availableThemes.join(", ")}',
      );
    }

    setTheme(arg);
    return TextCommandResult('Theme changed to: $arg');
  }
}

/// /terminal-setup — configure terminal integration.
class TerminalSetupCommand extends LocalCommand {
  @override
  String get name => 'terminal-setup';

  @override
  String get description => 'Configure terminal integration for optimal experience';

  @override
  List<String> get aliases => const ['setup-terminal'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final buffer = StringBuffer();
    buffer.writeln('Terminal Setup Guide');
    buffer.writeln('====================');
    buffer.writeln();
    buffer.writeln('Recommended configuration for best experience:');
    buffer.writeln();
    buffer.writeln('1. Shell Integration');
    buffer.writeln('   Add to your shell profile (~/.zshrc or ~/.bashrc):');
    buffer.writeln('     export CLAW_TERM=1');
    buffer.writeln();
    buffer.writeln('2. Font');
    buffer.writeln('   Use a Nerd Font for icon support:');
    buffer.writeln('     https://www.nerdfonts.com/');
    buffer.writeln();
    buffer.writeln('3. Terminal Emulator');
    buffer.writeln('   Recommended: iTerm2, Alacritty, Kitty, WezTerm');
    buffer.writeln('   Minimum: 80x24 terminal size, 256-color support');
    buffer.writeln();
    buffer.writeln('4. Environment variables');
    buffer.writeln('   ANTHROPIC_API_KEY — your API key');
    buffer.writeln('   CLAW_MODEL — default model (optional)');
    buffer.writeln('   CLAW_MAX_TOKENS — max output tokens (optional)');
    buffer.writeln();

    // Detect current terminal
    final term = Platform.environment['TERM'] ?? 'unknown';
    final termProgram = Platform.environment['TERM_PROGRAM'] ?? 'unknown';
    final colorterm = Platform.environment['COLORTERM'] ?? 'none';

    buffer.writeln('Current terminal:');
    buffer.writeln('  TERM=$term');
    buffer.writeln('  TERM_PROGRAM=$termProgram');
    buffer.writeln('  COLORTERM=$colorterm');

    return TextCommandResult(buffer.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Session Management
// ════════════════════════════════════════════════════════════════════════════

/// /resume — resume a previous session.
class ResumeCommand extends LocalCommand {
  final Future<List<String>> Function() listSessions;
  final Future<bool> Function(String sessionId) resumeSession;

  ResumeCommand({
    required this.listSessions,
    required this.resumeSession,
  });

  @override
  String get name => 'resume';

  @override
  String get description => 'Resume a previous conversation session';

  @override
  String? get argumentHint => '[<session-id>|last]';

  @override
  List<String> get aliases => const ['continue'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final arg = args.trim();

    if (arg.isEmpty) {
      final sessions = await listSessions();
      if (sessions.isEmpty) {
        return const TextCommandResult('No previous sessions found.');
      }
      final buffer = StringBuffer();
      buffer.writeln('Recent sessions:');
      for (final s in sessions.take(10)) {
        buffer.writeln('  $s');
      }
      buffer.writeln();
      buffer.writeln('Usage: /resume <session-id> or /resume last');
      return TextCommandResult(buffer.toString());
    }

    String sessionId;
    if (arg == 'last') {
      final sessions = await listSessions();
      if (sessions.isEmpty) {
        return const TextCommandResult('No previous sessions found.');
      }
      sessionId = sessions.first;
    } else {
      sessionId = arg;
    }

    final success = await resumeSession(sessionId);
    if (!success) {
      return TextCommandResult('Session not found: $sessionId');
    }
    return TextCommandResult('Resumed session: $sessionId');
  }
}

/// /status — show session status (tokens, cost, model, etc).
class StatusCommand extends LocalCommand {
  final String Function() getCurrentModel;
  final String Function() getSessionId;
  final int Function() getMessageCount;
  final int Function() getTokenCount;
  final String Function() getCwd;

  StatusCommand({
    required this.getCurrentModel,
    required this.getSessionId,
    required this.getMessageCount,
    required this.getTokenCount,
    required this.getCwd,
  });

  @override
  String get name => 'status';

  @override
  String get description => 'Show current session status and information';

  @override
  List<String> get aliases => const ['info'];

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final buffer = StringBuffer();
    buffer.writeln('Session Status');
    buffer.writeln('==============');
    buffer.writeln('  Session ID:  ${getSessionId()}');
    buffer.writeln('  Model:       ${getCurrentModel()}');
    buffer.writeln('  Messages:    ${getMessageCount()}');
    buffer.writeln('  Tokens used: ~${getTokenCount()}');
    buffer.writeln('  Working dir: ${getCwd()}');
    buffer.writeln('  Platform:    ${Platform.operatingSystem}');
    buffer.writeln('  Dart SDK:    ${Platform.version.split(' ').first}');
    return TextCommandResult(buffer.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Authentication
// ════════════════════════════════════════════════════════════════════════════

/// /login — authenticate with the API.
class LoginCommand extends LocalCommand {
  final Future<bool> Function(String apiKey) onLogin;
  final bool Function() isAuthenticated;

  LoginCommand({
    required this.onLogin,
    required this.isAuthenticated,
  });

  @override
  String get name => 'login';

  @override
  String get description => 'Authenticate with the Anthropic API';

  @override
  String? get argumentHint => '[<api-key>]';

  @override
  List<String> get aliases => const ['auth'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    if (isAuthenticated()) {
      return const TextCommandResult(
        'Already authenticated. Use /logout first to switch accounts.',
      );
    }

    final key = args.trim();
    if (key.isEmpty) {
      // Check environment
      final envKey = Platform.environment['ANTHROPIC_API_KEY'];
      if (envKey != null && envKey.isNotEmpty) {
        final success = await onLogin(envKey);
        if (success) {
          return const TextCommandResult(
            'Authenticated using ANTHROPIC_API_KEY from environment.',
          );
        }
        return const TextCommandResult(
          'ANTHROPIC_API_KEY found but authentication failed. '
          'Check that your key is valid.',
        );
      }
      return const TextCommandResult(
        'No API key provided.\n'
        'Usage: /login <api-key>\n'
        'Or set ANTHROPIC_API_KEY environment variable.',
      );
    }

    if (!key.startsWith('sk-ant-')) {
      return const TextCommandResult(
        'Invalid API key format. Anthropic keys start with "sk-ant-".',
      );
    }

    final success = await onLogin(key);
    if (success) {
      return const TextCommandResult('Authenticated successfully.');
    }
    return const TextCommandResult('Authentication failed. Check your API key.');
  }
}

/// /logout — clear credentials.
class LogoutCommand extends LocalCommand {
  final void Function() onLogout;
  final bool Function() isAuthenticated;

  LogoutCommand({
    required this.onLogout,
    required this.isAuthenticated,
  });

  @override
  String get name => 'logout';

  @override
  String get description => 'Clear stored API credentials';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    if (!isAuthenticated()) {
      return const TextCommandResult('Not currently authenticated.');
    }
    onLogout();
    return const TextCommandResult(
      'Credentials cleared. You will need to re-authenticate to continue.',
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MCP (Model Context Protocol)
// ════════════════════════════════════════════════════════════════════════════

/// /mcp — manage MCP servers.
class McpCommand extends LocalCommand {
  final Future<List<Map<String, dynamic>>> Function() listServers;
  final Future<bool> Function(String name, Map<String, dynamic> config) addServer;
  final Future<bool> Function(String name) removeServer;

  McpCommand({
    required this.listServers,
    required this.addServer,
    required this.removeServer,
  });

  @override
  String get name => 'mcp';

  @override
  String get description => 'Manage Model Context Protocol (MCP) servers';

  @override
  String? get argumentHint => '[list|add <name> <cmd>|remove <name>|status]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
      case 'status':
        return _listServers();
      case 'add':
        if (parts.length < 3) {
          return const TextCommandResult(
            'Usage: /mcp add <name> <command> [args...]\n'
            'Example: /mcp add filesystem npx -y @anthropic/mcp-filesystem',
          );
        }
        final serverName = parts[1];
        final command = parts[2];
        final serverArgs = parts.length > 3 ? parts.sublist(3) : <String>[];
        final config = {
          'command': command,
          'args': serverArgs,
        };
        final success = await addServer(serverName, config);
        if (success) {
          return TextCommandResult('Added MCP server: $serverName');
        }
        return TextCommandResult('Failed to add MCP server: $serverName');
      case 'remove':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /mcp remove <name>');
        }
        final success = await removeServer(parts[1]);
        if (success) {
          return TextCommandResult('Removed MCP server: ${parts[1]}');
        }
        return TextCommandResult('MCP server not found: ${parts[1]}');
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /mcp [list|add <name> <cmd>|remove <name>|status]',
        );
    }
  }

  Future<CommandResult> _listServers() async {
    final servers = await listServers();
    if (servers.isEmpty) {
      return const TextCommandResult(
        'No MCP servers configured.\n'
        'Add one with: /mcp add <name> <command> [args...]',
      );
    }
    final buffer = StringBuffer();
    buffer.writeln('MCP Servers (${servers.length}):');
    for (final server in servers) {
      final name = server['name'] ?? 'unnamed';
      final status = server['status'] ?? 'unknown';
      final tools = server['tools'] as int? ?? 0;
      buffer.writeln('  $name — $status ($tools tools)');
    }
    return TextCommandResult(buffer.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Agent & Task Management
// ════════════════════════════════════════════════════════════════════════════

/// /tasks — manage background tasks.
class TasksCommand extends LocalCommand {
  final Future<List<Map<String, dynamic>>> Function() listTasks;
  final Future<bool> Function(String taskId) cancelTask;

  TasksCommand({
    required this.listTasks,
    required this.cancelTask,
  });

  @override
  String get name => 'tasks';

  @override
  String get description => 'View and manage background tasks';

  @override
  String? get argumentHint => '[list|cancel <id>]';

  @override
  List<String> get aliases => const ['jobs'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
        return _listTasks();
      case 'cancel':
      case 'kill':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /tasks cancel <task-id>');
        }
        final success = await cancelTask(parts[1]);
        if (success) {
          return TextCommandResult('Cancelled task: ${parts[1]}');
        }
        return TextCommandResult('Task not found or already completed: ${parts[1]}');
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /tasks [list|cancel <id>]',
        );
    }
  }

  Future<CommandResult> _listTasks() async {
    final tasks = await listTasks();
    if (tasks.isEmpty) {
      return const TextCommandResult('No background tasks running.');
    }
    final buffer = StringBuffer();
    buffer.writeln('Background tasks (${tasks.length}):');
    for (final task in tasks) {
      final id = task['id'] ?? '?';
      final status = task['status'] ?? 'unknown';
      final desc = task['description'] ?? '';
      buffer.writeln('  [$id] $status — $desc');
    }
    return TextCommandResult(buffer.toString());
  }
}

/// /agents — manage spawned sub-agents.
class AgentsCommand extends LocalCommand {
  final Future<List<Map<String, dynamic>>> Function() listAgents;
  final Future<bool> Function(String agentId) cancelAgent;

  AgentsCommand({
    required this.listAgents,
    required this.cancelAgent,
  });

  @override
  String get name => 'agents';

  @override
  String get description => 'View and manage spawned sub-agents';

  @override
  String? get argumentHint => '[list|cancel <id>]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
        return _listAgents();
      case 'cancel':
      case 'kill':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /agents cancel <agent-id>');
        }
        final success = await cancelAgent(parts[1]);
        if (success) {
          return TextCommandResult('Cancelled agent: ${parts[1]}');
        }
        return TextCommandResult('Agent not found: ${parts[1]}');
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /agents [list|cancel <id>]',
        );
    }
  }

  Future<CommandResult> _listAgents() async {
    final agents = await listAgents();
    if (agents.isEmpty) {
      return const TextCommandResult('No active sub-agents.');
    }
    final buffer = StringBuffer();
    buffer.writeln('Active agents (${agents.length}):');
    for (final agent in agents) {
      final id = agent['id'] ?? '?';
      final status = agent['status'] ?? 'unknown';
      final task = agent['task'] ?? '';
      buffer.writeln('  [$id] $status — $task');
    }
    return TextCommandResult(buffer.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Development
// ════════════════════════════════════════════════════════════════════════════

/// /init — initialize project configuration (.neomclaw/).
class InitCommand extends LocalCommand {
  @override
  String get name => 'init';

  @override
  String get description => 'Initialize project configuration in .neomclaw/';

  @override
  String? get argumentHint => '[--force]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final force = args.trim() == '--force';
    final projectDir = Directory('${context.cwd}/.neomclaw');

    if (await projectDir.exists() && !force) {
      return const TextCommandResult(
        'Project already initialized (.neomclaw/ exists).\n'
        'Use /init --force to reinitialize.',
      );
    }

    try {
      // Create .neomclaw directory structure
      await projectDir.create(recursive: true);

      // Create settings.json
      final settingsFile = File('${projectDir.path}/settings.json');
      if (!await settingsFile.exists() || force) {
        await settingsFile.writeAsString(
          '{\n'
          '  "permissions": {},\n'
          '  "hooks": {},\n'
          '  "mcpServers": {}\n'
          '}\n',
        );
      }

      // Create NEOMCLAW.md
      final neomClawFile = File('${context.cwd}/NEOMCLAW.md');
      if (!await neomClawFile.exists() || force) {
        await neomClawFile.writeAsString(
          '# Project Instructions\n\n'
          'Add project-specific instructions for the AI assistant here.\n\n'
          '## Build & Test\n\n'
          '- Build: `<your build command>`\n'
          '- Test: `<your test command>`\n'
          '- Lint: `<your lint command>`\n\n'
          '## Code Style\n\n'
          '- Follow existing patterns in the codebase\n',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Project initialized:');
      buffer.writeln('  Created .neomclaw/settings.json');
      buffer.writeln('  Created NEOMCLAW.md');
      buffer.writeln();
      buffer.writeln('Edit NEOMCLAW.md to add project-specific instructions.');
      return TextCommandResult(buffer.toString());
    } catch (e) {
      return TextCommandResult('Initialization failed: $e');
    }
  }
}

/// /bug — report a bug.
class BugCommand extends LocalCommand {
  @override
  String get name => 'bug';

  @override
  String get description => 'Report a bug or issue';

  @override
  String? get argumentHint => '[<description>]';

  @override
  List<String> get aliases => const ['report-bug', 'feedback'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final description = args.trim();

    final buffer = StringBuffer();
    buffer.writeln('Bug Report');
    buffer.writeln('==========');
    buffer.writeln();

    // Collect system info
    buffer.writeln('System information:');
    buffer.writeln('  Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('  Dart: ${Platform.version.split(' ').first}');
    buffer.writeln('  CWD: ${context.cwd}');
    buffer.writeln();

    if (description.isNotEmpty) {
      buffer.writeln('Description: $description');
      buffer.writeln();
      buffer.writeln('Bug report prepared. To submit:');
      buffer.writeln('  1. Copy this output');
      buffer.writeln('  2. Open https://github.com/anthropics/neom-claw/issues/new');
      buffer.writeln('  3. Paste and submit');
    } else {
      buffer.writeln('Usage: /bug <description of the issue>');
      buffer.writeln();
      buffer.writeln('Include steps to reproduce if possible.');
      buffer.writeln('The report will include system info automatically.');
    }

    return TextCommandResult(buffer.toString());
  }
}

/// /doctor — check system health and dependencies.
class DoctorCommand extends LocalCommand {
  @override
  String get name => 'doctor';

  @override
  String get description => 'Check system health and configuration';

  @override
  List<String> get aliases => const ['health', 'check'];

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final buffer = StringBuffer();
    buffer.writeln('System Health Check');
    buffer.writeln('===================');
    buffer.writeln();

    // Check API key
    final hasApiKey = Platform.environment.containsKey('ANTHROPIC_API_KEY');
    buffer.writeln(_check('API Key', hasApiKey, 'Set ANTHROPIC_API_KEY'));

    // Check git
    final gitResult = await _runCommand('git', ['--version']);
    buffer.writeln(_check('Git', gitResult != null, 'Install git'));

    // Check .neomclaw directory
    final neomClawDir = Directory('${context.cwd}/.neomclaw');
    final hasNeomClawDir = await neomClawDir.exists();
    buffer.writeln(_check('.neomclaw/ config', hasNeomClawDir, 'Run /init'));

    // Check NEOMCLAW.md
    final claudeMd = File('${context.cwd}/NEOMCLAW.md');
    final hasNeomClawMd = await claudeMd.exists();
    buffer.writeln(_check('NEOMCLAW.md', hasNeomClawMd, 'Run /init or create manually'));

    // Check ripgrep
    final rgResult = await _runCommand('rg', ['--version']);
    buffer.writeln(_check('ripgrep (rg)', rgResult != null, 'brew install ripgrep'));

    // Check node (for MCP)
    final nodeResult = await _runCommand('node', ['--version']);
    buffer.writeln(_check('Node.js (MCP)', nodeResult != null, 'Install Node.js'));

    // Check gh CLI
    final ghResult = await _runCommand('gh', ['--version']);
    buffer.writeln(_check('GitHub CLI (gh)', ghResult != null, 'brew install gh'));

    // Check jq
    final jqResult = await _runCommand('jq', ['--version']);
    buffer.writeln(_check('jq', jqResult != null, 'brew install jq'));

    buffer.writeln();

    // OS info
    buffer.writeln('Environment:');
    buffer.writeln('  OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('  Dart: ${Platform.version.split(' ').first}');
    buffer.writeln('  Shell: ${Platform.environment['SHELL'] ?? 'unknown'}');
    buffer.writeln('  Terminal: ${Platform.environment['TERM_PROGRAM'] ?? 'unknown'}');

    return TextCommandResult(buffer.toString());
  }

  String _check(String label, bool ok, String fixHint) {
    final icon = ok ? '[OK]' : '[!!]';
    final suffix = ok ? '' : ' — $fixHint';
    return '  $icon $label$suffix';
  }

  Future<String?> _runCommand(String executable, List<String> args) async {
    try {
      final result = await Process.run(executable, args);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// /release-notes — show latest changes and version info.
class ReleaseNotesCommand extends LocalCommand {
  final String Function() getVersion;

  ReleaseNotesCommand({required this.getVersion});

  @override
  String get name => 'release-notes';

  @override
  String get description => 'Show version info and recent changes';

  @override
  List<String> get aliases => const ['changelog', 'version', 'whatsnew'];

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final version = getVersion();
    final buffer = StringBuffer();
    buffer.writeln('Claw v$version');
    buffer.writeln();
    buffer.writeln('To view the full changelog, visit:');
    buffer.writeln('  https://github.com/anthropics/neom-claw/releases');
    buffer.writeln();
    buffer.writeln('To check for updates:');
    buffer.writeln('  flutter pub upgrade');
    return TextCommandResult(buffer.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Input & Output
// ════════════════════════════════════════════════════════════════════════════

/// /listen — start voice/dictation input.
class ListenCommand extends LocalCommand {
  final void Function(bool) onListenToggle;
  final bool Function() isListening;

  ListenCommand({
    required this.onListenToggle,
    required this.isListening,
  });

  @override
  String get name => 'listen';

  @override
  String get description => 'Toggle voice/dictation input mode';

  @override
  List<String> get aliases => const ['voice', 'dictate'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final current = isListening();
    final newState = !current;
    onListenToggle(newState);

    if (newState) {
      return const TextCommandResult(
        'Listening mode enabled. Speak your input.\n'
        'Use /listen again to stop.',
      );
    }
    return const TextCommandResult('Listening mode disabled.');
  }
}

/// /vim — toggle vim-style keybindings.
class VimCommand extends LocalCommand {
  final void Function(bool) onVimToggle;
  final bool Function() isVimMode;

  VimCommand({
    required this.onVimToggle,
    required this.isVimMode,
  });

  @override
  String get name => 'vim';

  @override
  String get description => 'Toggle vim-style key bindings';

  @override
  List<String> get aliases => const ['vi'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    if (args.trim() == 'on') {
      onVimToggle(true);
      return const TextCommandResult('Vim mode enabled.');
    }
    if (args.trim() == 'off') {
      onVimToggle(false);
      return const TextCommandResult('Vim mode disabled.');
    }

    final current = isVimMode();
    final newState = !current;
    onVimToggle(newState);
    return TextCommandResult(
      'Vim mode ${newState ? "enabled" : "disabled"}.',
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// IDE Integration
// ════════════════════════════════════════════════════════════════════════════

/// /ide — manage IDE integrations.
class IdeCommand extends LocalCommand {
  static const _supportedIdes = ['vscode', 'jetbrains', 'neovim', 'emacs'];

  final String? Function() getConnectedIde;
  final Future<bool> Function(String ide) connectIde;
  final void Function() disconnectIde;

  IdeCommand({
    required this.getConnectedIde,
    required this.connectIde,
    required this.disconnectIde,
  });

  @override
  String get name => 'ide';

  @override
  String get description => 'Manage IDE integrations';

  @override
  String? get argumentHint => '[status|connect <ide>|disconnect]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'status';

    switch (subcommand) {
      case 'status':
        final ide = getConnectedIde();
        if (ide == null) {
          return const TextCommandResult(
            'No IDE connected.\n'
            'Connect with: /ide connect <vscode|jetbrains|neovim|emacs>',
          );
        }
        return TextCommandResult('Connected to: $ide');
      case 'connect':
        if (parts.length < 2) {
          return TextCommandResult(
            'Usage: /ide connect <ide>\n'
            'Supported: ${_supportedIdes.join(", ")}',
          );
        }
        final ide = parts[1].toLowerCase();
        if (!_supportedIdes.contains(ide)) {
          return TextCommandResult(
            'Unsupported IDE: $ide\n'
            'Supported: ${_supportedIdes.join(", ")}',
          );
        }
        final success = await connectIde(ide);
        if (success) {
          return TextCommandResult('Connected to $ide.');
        }
        return TextCommandResult(
          'Failed to connect to $ide. Ensure the extension is installed.',
        );
      case 'disconnect':
        disconnectIde();
        return const TextCommandResult('IDE disconnected.');
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /ide [status|connect <ide>|disconnect]',
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Prompt
// ════════════════════════════════════════════════════════════════════════════

/// /prompt — set or view system prompt additions.
class PromptCommand extends LocalCommand {
  final String Function() getPromptAddition;
  final void Function(String) setPromptAddition;

  PromptCommand({
    required this.getPromptAddition,
    required this.setPromptAddition,
  });

  @override
  String get name => 'prompt';

  @override
  String get description => 'View or set additional system prompt instructions';

  @override
  String? get argumentHint => '[show|set <text>|clear]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'show';

    switch (subcommand) {
      case 'show':
      case 'view':
        final current = getPromptAddition();
        if (current.isEmpty) {
          return const TextCommandResult(
            'No additional prompt instructions set.\n'
            'Use /prompt set <text> to add instructions.',
          );
        }
        return TextCommandResult(
          'Current prompt addition:\n$current',
        );
      case 'set':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /prompt set <text>');
        }
        final text = parts.sublist(1).join(' ');
        setPromptAddition(text);
        return TextCommandResult(
          'Prompt addition set (${text.length} characters).',
        );
      case 'clear':
        setPromptAddition('');
        return const TextCommandResult('Prompt addition cleared.');
      case 'append':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /prompt append <text>');
        }
        final current = getPromptAddition();
        final text = parts.sublist(1).join(' ');
        final newPrompt = current.isEmpty ? text : '$current\n$text';
        setPromptAddition(newPrompt);
        return TextCommandResult(
          'Appended to prompt addition (${newPrompt.length} characters total).',
        );
      default:
        // Treat entire args as a prompt to set
        setPromptAddition(args.trim());
        return TextCommandResult(
          'Prompt addition set (${args.trim().length} characters).',
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Export
// ════════════════════════════════════════════════════════════════════════════

/// /export — export conversation to a file.
class ExportCommand extends LocalCommand {
  final List<Map<String, dynamic>> Function() getConversation;

  ExportCommand({required this.getConversation});

  @override
  String get name => 'export';

  @override
  String get description => 'Export conversation to a markdown file';

  @override
  String? get argumentHint => '[<filename>]';

  @override
  List<String> get aliases => const ['save'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final conversation = getConversation();
    if (conversation.isEmpty) {
      return const TextCommandResult('Nothing to export — conversation is empty.');
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final filename = args.trim().isNotEmpty
        ? args.trim()
        : 'conversation-$timestamp.md';

    final path = filename.startsWith('/')
        ? filename
        : '${context.cwd}/$filename';

    try {
      final buffer = StringBuffer();
      buffer.writeln('# Conversation Export');
      buffer.writeln();
      buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();

      for (final msg in conversation) {
        final role = msg['role'] ?? 'unknown';
        final content = msg['content'] ?? '';
        final roleLabel = role == 'user' ? 'User' : 'Assistant';

        buffer.writeln('## $roleLabel');
        buffer.writeln();
        buffer.writeln(content);
        buffer.writeln();
        buffer.writeln('---');
        buffer.writeln();
      }

      final file = File(path);
      await file.writeAsString(buffer.toString());
      return TextCommandResult('Conversation exported to: $path');
    } catch (e) {
      return TextCommandResult('Export failed: $e');
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Undo
// ════════════════════════════════════════════════════════════════════════════

/// /undo — undo the last file change made by the assistant.
class UndoCommand extends LocalCommand {
  final Future<Map<String, dynamic>?> Function() getLastChange;
  final Future<bool> Function(String changeId) revertChange;

  UndoCommand({
    required this.getLastChange,
    required this.revertChange,
  });

  @override
  String get name => 'undo';

  @override
  String get description => 'Undo the last file change made by the assistant';

  @override
  List<String> get aliases => const ['revert'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final lastChange = await getLastChange();
    if (lastChange == null) {
      return const TextCommandResult(
        'Nothing to undo. No file changes recorded in this session.',
      );
    }

    final changeId = lastChange['id'] as String? ?? '';
    final filePath = lastChange['file'] as String? ?? 'unknown';
    final toolName = lastChange['tool'] as String? ?? 'unknown';

    final success = await revertChange(changeId);
    if (success) {
      return TextCommandResult(
        'Reverted $toolName on $filePath.',
      );
    }
    return TextCommandResult(
      'Failed to undo change on $filePath. '
      'The file may have been modified since.',
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Profile
// ════════════════════════════════════════════════════════════════════════════

/// /profile — view usage profile and statistics.
class ProfileCommand extends LocalCommand {
  final Future<Map<String, dynamic>> Function() getProfile;

  ProfileCommand({required this.getProfile});

  @override
  String get name => 'profile';

  @override
  String get description => 'View usage statistics and profile information';

  @override
  List<String> get aliases => const ['usage', 'stats'];

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final profile = await getProfile();

    final buffer = StringBuffer();
    buffer.writeln('Usage Profile');
    buffer.writeln('=============');
    buffer.writeln();

    final totalSessions = profile['totalSessions'] ?? 0;
    final totalTokens = profile['totalTokens'] ?? 0;
    final totalMessages = profile['totalMessages'] ?? 0;
    final totalToolUses = profile['totalToolUses'] ?? 0;
    final topTools = profile['topTools'] as List<dynamic>? ?? [];
    final activeSince = profile['activeSince'] as String? ?? 'unknown';

    buffer.writeln('  Active since:    $activeSince');
    buffer.writeln('  Total sessions:  $totalSessions');
    buffer.writeln('  Total messages:  $totalMessages');
    buffer.writeln('  Total tokens:    $totalTokens');
    buffer.writeln('  Tool invocations: $totalToolUses');

    if (topTools.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('  Most used tools:');
      for (final tool in topTools.take(5)) {
        final name = tool['name'] ?? '?';
        final count = tool['count'] ?? 0;
        buffer.writeln('    $name: $count');
      }
    }

    return TextCommandResult(buffer.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Tools
// ════════════════════════════════════════════════════════════════════════════

/// /tools — list available tools.
class ToolsCommand extends LocalCommand {
  final List<Map<String, dynamic>> Function() getTools;

  ToolsCommand({required this.getTools});

  @override
  String get name => 'tools';

  @override
  String get description => 'List all available tools and their status';

  @override
  String? get argumentHint => '[<tool-name>]';

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final tools = getTools();
    final filter = args.trim().toLowerCase();

    if (filter.isNotEmpty) {
      // Show details for a specific tool
      final tool = tools.firstWhere(
        (t) => (t['name'] as String? ?? '').toLowerCase() == filter,
        orElse: () => <String, dynamic>{},
      );
      if (tool.isEmpty) {
        return TextCommandResult('Tool not found: $filter');
      }
      final buffer = StringBuffer();
      buffer.writeln('Tool: ${tool['name']}');
      buffer.writeln('  Description: ${tool['description'] ?? 'none'}');
      buffer.writeln('  Enabled: ${tool['enabled'] ?? true}');
      buffer.writeln('  Read-only: ${tool['readOnly'] ?? false}');
      buffer.writeln('  Destructive: ${tool['destructive'] ?? false}');
      if (tool['source'] != null) {
        buffer.writeln('  Source: ${tool['source']}');
      }
      return TextCommandResult(buffer.toString());
    }

    if (tools.isEmpty) {
      return const TextCommandResult('No tools available.');
    }

    // Group tools by source
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final tool in tools) {
      final source = tool['source'] as String? ?? 'builtin';
      grouped.putIfAbsent(source, () => []).add(tool);
    }

    final buffer = StringBuffer();
    buffer.writeln('Available Tools (${tools.length}):');

    for (final entry in grouped.entries) {
      buffer.writeln();
      buffer.writeln('  [${entry.key}]');
      for (final tool in entry.value) {
        final name = tool['name'] ?? '?';
        final enabled = tool['enabled'] ?? true;
        final marker = enabled ? '' : ' (disabled)';
        final desc = tool['description'] as String? ?? '';
        final shortDesc = desc.length > 50 ? '${desc.substring(0, 47)}...' : desc;
        buffer.writeln('    $name$marker — $shortDesc');
      }
    }

    buffer.writeln();
    buffer.writeln('Use /tools <name> for details on a specific tool.');
    return TextCommandResult(buffer.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Registration
// ════════════════════════════════════════════════════════════════════════════

/// Configuration container for wiring up extended commands with their
/// required callbacks and dependencies.
class ExtendedCommandsDeps {
  // Navigation
  final void Function(String) onDirectoryChange;
  final String Function() getCurrentDir;

  // Configuration
  final Map<String, dynamic> Function() getConfig;
  final void Function(String key, dynamic value) setConfig;
  final Map<String, String> Function() getPermissions;
  final void Function(String tool, String rule) setPermission;
  final Map<String, List<String>> Function() getHooks;
  final void Function(String event, String command) addHook;
  final void Function(String event, int index) removeHook;
  final String Function() getCurrentTheme;
  final void Function(String) setTheme;

  // Session
  final Future<List<String>> Function() listSessions;
  final Future<bool> Function(String) resumeSession;
  final String Function() getCurrentModel;
  final String Function() getSessionId;
  final int Function() getMessageCount;
  final int Function() getTokenCount;
  final String Function() getCwd;

  // Auth
  final Future<bool> Function(String) onLogin;
  final bool Function() isAuthenticated;
  final void Function() onLogout;

  // MCP
  final Future<List<Map<String, dynamic>>> Function() listMcpServers;
  final Future<bool> Function(String, Map<String, dynamic>) addMcpServer;
  final Future<bool> Function(String) removeMcpServer;

  // Tasks / Agents
  final Future<List<Map<String, dynamic>>> Function() listTasks;
  final Future<bool> Function(String) cancelTask;
  final Future<List<Map<String, dynamic>>> Function() listAgents;
  final Future<bool> Function(String) cancelAgent;

  // Version
  final String Function() getVersion;

  // Input
  final void Function(bool) onListenToggle;
  final bool Function() isListening;
  final void Function(bool) onVimToggle;
  final bool Function() isVimMode;

  // IDE
  final String? Function() getConnectedIde;
  final Future<bool> Function(String) connectIde;
  final void Function() disconnectIde;

  // Prompt
  final String Function() getPromptAddition;
  final void Function(String) setPromptAddition;

  // Export
  final List<Map<String, dynamic>> Function() getConversation;

  // Undo
  final Future<Map<String, dynamic>?> Function() getLastChange;
  final Future<bool> Function(String) revertChange;

  // Profile
  final Future<Map<String, dynamic>> Function() getProfile;

  // Tools
  final List<Map<String, dynamic>> Function() getTools;

  const ExtendedCommandsDeps({
    required this.onDirectoryChange,
    required this.getCurrentDir,
    required this.getConfig,
    required this.setConfig,
    required this.getPermissions,
    required this.setPermission,
    required this.getHooks,
    required this.addHook,
    required this.removeHook,
    required this.getCurrentTheme,
    required this.setTheme,
    required this.listSessions,
    required this.resumeSession,
    required this.getCurrentModel,
    required this.getSessionId,
    required this.getMessageCount,
    required this.getTokenCount,
    required this.getCwd,
    required this.onLogin,
    required this.isAuthenticated,
    required this.onLogout,
    required this.listMcpServers,
    required this.addMcpServer,
    required this.removeMcpServer,
    required this.listTasks,
    required this.cancelTask,
    required this.listAgents,
    required this.cancelAgent,
    required this.getVersion,
    required this.onListenToggle,
    required this.isListening,
    required this.onVimToggle,
    required this.isVimMode,
    required this.getConnectedIde,
    required this.connectIde,
    required this.disconnectIde,
    required this.getPromptAddition,
    required this.setPromptAddition,
    required this.getConversation,
    required this.getLastChange,
    required this.revertChange,
    required this.getProfile,
    required this.getTools,
  });
}

/// Register all extended commands with the given dependencies.
List<LocalCommand> registerExtendedCommands(ExtendedCommandsDeps deps) {
  return [
    // Navigation & Context
    AddDirCommand(),
    CdCommand(
      onDirectoryChange: deps.onDirectoryChange,
      getCurrentDir: deps.getCurrentDir,
    ),

    // Configuration
    ConfigCommand(
      getConfig: deps.getConfig,
      setConfig: deps.setConfig,
    ),
    PermissionsCommand(
      getPermissions: deps.getPermissions,
      setPermission: deps.setPermission,
    ),
    HooksCommand(
      getHooks: deps.getHooks,
      addHook: deps.addHook,
      removeHook: deps.removeHook,
    ),
    ThemeCommand(
      getCurrentTheme: deps.getCurrentTheme,
      setTheme: deps.setTheme,
    ),
    TerminalSetupCommand(),

    // Session Management
    ResumeCommand(
      listSessions: deps.listSessions,
      resumeSession: deps.resumeSession,
    ),
    StatusCommand(
      getCurrentModel: deps.getCurrentModel,
      getSessionId: deps.getSessionId,
      getMessageCount: deps.getMessageCount,
      getTokenCount: deps.getTokenCount,
      getCwd: deps.getCwd,
    ),

    // Authentication
    LoginCommand(
      onLogin: deps.onLogin,
      isAuthenticated: deps.isAuthenticated,
    ),
    LogoutCommand(
      onLogout: deps.onLogout,
      isAuthenticated: deps.isAuthenticated,
    ),

    // MCP
    McpCommand(
      listServers: deps.listMcpServers,
      addServer: deps.addMcpServer,
      removeServer: deps.removeMcpServer,
    ),

    // Agent & Task Management
    TasksCommand(
      listTasks: deps.listTasks,
      cancelTask: deps.cancelTask,
    ),
    AgentsCommand(
      listAgents: deps.listAgents,
      cancelAgent: deps.cancelAgent,
    ),

    // Development
    InitCommand(),
    BugCommand(),
    DoctorCommand(),
    ReleaseNotesCommand(getVersion: deps.getVersion),

    // Input & Output
    ListenCommand(
      onListenToggle: deps.onListenToggle,
      isListening: deps.isListening,
    ),
    VimCommand(
      onVimToggle: deps.onVimToggle,
      isVimMode: deps.isVimMode,
    ),

    // IDE Integration
    IdeCommand(
      getConnectedIde: deps.getConnectedIde,
      connectIde: deps.connectIde,
      disconnectIde: deps.disconnectIde,
    ),

    // Prompt
    PromptCommand(
      getPromptAddition: deps.getPromptAddition,
      setPromptAddition: deps.setPromptAddition,
    ),

    // Export
    ExportCommand(getConversation: deps.getConversation),

    // Undo
    UndoCommand(
      getLastChange: deps.getLastChange,
      revertChange: deps.revertChange,
    ),

    // Profile
    ProfileCommand(getProfile: deps.getProfile),

    // Tools
    ToolsCommand(getTools: deps.getTools),
  ];
}
