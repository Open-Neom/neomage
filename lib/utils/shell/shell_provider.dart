// Shell provider — port of neom_claw/src/utils/shell/.
// Shell detection, environment setup, command building, read-only validation.

import 'package:neom_claw/core/platform/claw_io.dart';

/// Shell type.
enum ShellType { bash, zsh, sh, fish, powershell, cmd }

/// Shell provider configuration.
class ShellConfig {
  final ShellType type;
  final String shellPath;
  final bool detached;
  final Map<String, String> environmentOverrides;

  const ShellConfig({
    required this.type,
    required this.shellPath,
    this.detached = false,
    this.environmentOverrides = const {},
  });
}

/// Detect the user's shell.
ShellConfig detectShell({Map<String, String>? env}) {
  final environment = env ?? Platform.environment;

  if (Platform.isWindows) {
    final comspec = environment['COMSPEC'];
    if (comspec != null && comspec.toLowerCase().contains('powershell')) {
      return ShellConfig(type: ShellType.powershell, shellPath: comspec);
    }
    return ShellConfig(type: ShellType.cmd, shellPath: comspec ?? 'cmd.exe');
  }

  final shell = environment['SHELL'] ?? '/bin/sh';
  final shellName = shell.split('/').last;

  final type = switch (shellName) {
    'bash' => ShellType.bash,
    'zsh' => ShellType.zsh,
    'fish' => ShellType.fish,
    'sh' || 'dash' => ShellType.sh,
    _ => ShellType.sh,
  };

  return ShellConfig(type: type, shellPath: shell);
}

/// Build the command and arguments for shell execution.
({String executable, List<String> args}) buildExecCommand(
  String command,
  ShellConfig config, {
  String? workingDirectory,
  bool trackCwd = false,
}) {
  switch (config.type) {
    case ShellType.bash:
    case ShellType.zsh:
    case ShellType.sh:
    case ShellType.fish:
      final args = ['-c', command];
      return (executable: config.shellPath, args: args);

    case ShellType.powershell:
      return (
        executable: config.shellPath,
        args: ['-NoProfile', '-NonInteractive', '-Command', command],
      );

    case ShellType.cmd:
      return (executable: config.shellPath, args: ['/c', command]);
  }
}

/// Build environment overrides for a command execution.
Map<String, String> buildEnvironment(
  ShellConfig config, {
  Map<String, String>? additional,
  String? workingDirectory,
}) {
  final env = <String, String>{
    // Disable interactive features
    'TERM': 'dumb',
    'GIT_TERMINAL_PROMPT': '0',
    'NEOMCLAWCODE': '1',
    // Disable colors in some tools
    'NO_COLOR': '1',
    'FORCE_COLOR': '0',
    // Apply config overrides
    ...config.environmentOverrides,
    // Apply additional overrides
    ...?additional,
  };

  return env;
}

// ── Read-Only Command Validation ──

/// Safe git subcommands for read-only mode.
const safeGitSubcommands = <String, Set<String>>{
  'log': {
    '--oneline',
    '--graph',
    '--all',
    '--pretty',
    '--format',
    '--stat',
    '--shortstat',
    '--name-only',
    '--name-status',
    '--numstat',
    '--author',
    '--since',
    '--until',
    '--grep',
    '-n',
    '--follow',
    '--diff-filter',
    '--no-merges',
    '--merges',
    '--first-parent',
    '--ancestry-path',
    '--topo-order',
    '--date-order',
  },
  'show': {
    '--stat',
    '--name-only',
    '--name-status',
    '--format',
    '--pretty',
    '--no-patch',
    '--raw',
    '--word-diff',
  },
  'diff': {
    '--stat',
    '--shortstat',
    '--name-only',
    '--name-status',
    '--numstat',
    '--no-color',
    '--color',
    '--word-diff',
    '--unified',
    '--cached',
    '--staged',
    '-U',
  },
  'status': {'--short', '-s', '--porcelain', '--branch', '-b', '--untracked'},
  'branch': {
    '--list',
    '-l',
    '-a',
    '--all',
    '-r',
    '--remote',
    '--verbose',
    '-v',
    '--contains',
  },
  'tag': {'--list', '-l', '-n', '--contains', '--sort'},
  'remote': {'show', '-v', '--verbose'},
  'blame': {'--date', '-e', '-w', '-M', '-C', '-L'},
  'rev-parse': {'--short', '--abbrev-ref', '--show-toplevel', '--git-dir'},
  'rev-list': {'--count', '--all', '--since', '--until', '--author'},
  'ls-files': {'-m', '--modified', '-o', '--others', '--ignored'},
  'ls-tree': {'-r', '--name-only', '-l', '--long'},
  'cat-file': {'-t', '-s', '-p', '-e'},
  'shortlog': {'-s', '-n', '--summary', '--numbered'},
  'describe': {'--tags', '--always', '--abbrev', '--long'},
  'reflog': {'show', '--format', '--date', '-n'},
  'stash': {'list', 'show'},
  'config': {'--get', '--get-all', '--list', '-l'},
  'worktree': {'list'},
};

/// Safe npm/yarn/pnpm subcommands (read-only).
const safePackageManagerSubcommands = {
  'list',
  'ls',
  'info',
  'view',
  'show',
  'outdated',
  'audit',
  'why',
  'explain',
  'bin',
  'root',
  'prefix',
  'config',
};

/// Safe pip subcommands (read-only).
const safePipSubcommands = {'list', 'show', 'freeze', 'check'};

/// Safe docker subcommands (read-only).
const safeDockerSubcommands = {
  'inspect',
  'images',
  'ps',
  'logs',
  'port',
  'top',
  'stats',
  'diff',
  'history',
  'version',
  'info',
};

/// Safe gh (GitHub CLI) subcommands (read-only).
const safeGhSubcommands = {
  'view',
  'list',
  'status',
  'diff',
  'comment',
  'checks',
};

/// Flag argument types for read-only validation.
enum FlagArgType { none, number, string, char, braces, eof }

/// Validate a command for read-only mode.
///
/// Returns null if the command is safe, or a reason string if it's not.
String? validateReadOnlyCommand(String command) {
  final segments = command.split(RegExp(r'\s*[|;&]\s*'));

  for (final seg in segments) {
    final trimmed = seg.trim();
    if (trimmed.isEmpty) continue;

    // Strip env var prefixes
    var parts = trimmed.split(RegExp(r'\s+'));
    while (parts.isNotEmpty && parts.first.contains('=')) {
      parts = parts.sublist(1);
    }
    if (parts.isEmpty) continue;

    final cmd = parts.first;
    final args = parts.sublist(1);

    // Check for output redirection
    if (trimmed.contains('>') || trimmed.contains('>>')) {
      return 'Output redirection not allowed in read-only mode';
    }

    // Check for process substitution
    if (trimmed.contains('<(') || trimmed.contains('>(')) {
      return 'Process substitution not allowed in read-only mode';
    }

    // Check for background execution
    if (trimmed.endsWith('&') && !trimmed.endsWith('&&')) {
      return 'Background execution not allowed in read-only mode';
    }

    // Validate specific commands
    final validation = _validateReadOnlyCmd(cmd, args);
    if (validation != null) return validation;
  }

  return null;
}

String? _validateReadOnlyCmd(String cmd, List<String> args) {
  // Safe inspection commands
  const alwaysSafe = {
    'cat',
    'head',
    'tail',
    'less',
    'more',
    'wc',
    'stat',
    'file',
    'strings',
    'xxd',
    'hexdump',
    'od',
    'readlink',
    'realpath',
    'ls',
    'tree',
    'du',
    'df',
    'lsof',
    'grep',
    'rg',
    'ag',
    'ack',
    'find',
    'fd',
    'locate',
    'which',
    'whereis',
    'type',
    'command',
    'jq',
    'yq',
    'awk',
    'cut',
    'sort',
    'uniq',
    'tr',
    'column',
    'paste',
    'comm',
    'diff',
    'cmp',
    'uname',
    'hostname',
    'whoami',
    'id',
    'groups',
    'date',
    'uptime',
    'free',
    'ps',
    'top',
    'nproc',
    'lscpu',
    'env',
    'printenv',
    'echo',
    'printf',
    'true',
    'false',
  };

  if (alwaysSafe.contains(cmd)) {
    // Check sed for -i flag
    if (cmd == 'sed' &&
        (args.contains('-i') || args.any((a) => a.startsWith('-i')))) {
      return 'sed -i (in-place edit) not allowed in read-only mode';
    }
    return null;
  }

  // Git commands
  if (cmd == 'git') {
    if (args.isEmpty) return null; // bare "git" is fine
    final subCmd = args.first;
    if (safeGitSubcommands.containsKey(subCmd)) return null;
    return 'git $subCmd not allowed in read-only mode';
  }

  // Package managers
  if (cmd == 'npm' || cmd == 'yarn' || cmd == 'pnpm') {
    if (args.isEmpty) return '$cmd requires a subcommand';
    if (safePackageManagerSubcommands.contains(args.first)) return null;
    return '$cmd ${args.first} not allowed in read-only mode';
  }

  // pip
  if (cmd == 'pip' || cmd == 'pip3') {
    if (args.isEmpty) return '$cmd requires a subcommand';
    if (safePipSubcommands.contains(args.first)) return null;
    return '$cmd ${args.first} not allowed in read-only mode';
  }

  // Docker
  if (cmd == 'docker') {
    if (args.isEmpty) return 'docker requires a subcommand';
    if (safeDockerSubcommands.contains(args.first)) return null;
    return 'docker ${args.first} not allowed in read-only mode';
  }

  // GitHub CLI
  if (cmd == 'gh') {
    if (args.length < 2) return 'gh requires a resource and subcommand';
    if (safeGhSubcommands.contains(args[1])) return null;
    return 'gh ${args[0]} ${args[1]} not allowed in read-only mode';
  }

  return '$cmd not allowed in read-only mode';
}

// ── Shell Profile Detection ──

/// Get the user's shell profile file.
String? getShellProfile(ShellType type) {
  final home = Platform.environment['HOME'];
  if (home == null) return null;

  return switch (type) {
    ShellType.bash => '$home/.bashrc',
    ShellType.zsh => '$home/.zshrc',
    ShellType.fish => '$home/.config/fish/config.fish',
    ShellType.sh => '$home/.profile',
    ShellType.powershell => null, // Uses $PROFILE
    ShellType.cmd => null,
  };
}

/// Get the user's shell history file.
String? getShellHistoryFile(ShellType type) {
  final home = Platform.environment['HOME'];
  if (home == null) return null;

  return switch (type) {
    ShellType.bash => '$home/.bash_history',
    ShellType.zsh => '$home/.zsh_history',
    ShellType.fish => '$home/.local/share/fish/fish_history',
    _ => null,
  };
}
