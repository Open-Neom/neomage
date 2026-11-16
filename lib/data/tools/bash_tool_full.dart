// BashTool full — port of neomage/src/tools/BashTool/.
// Complete shell command execution with security, sandboxing, output handling.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';
import 'package:path/path.dart' as p;

/// Bash tool input.
class BashToolInput {
  final String command;
  final int? timeoutMs;
  final String? description;
  final bool runInBackground;
  final bool dangerouslyDisableSandbox;

  const BashToolInput({
    required this.command,
    this.timeoutMs,
    this.description,
    this.runInBackground = false,
    this.dangerouslyDisableSandbox = false,
  });

  factory BashToolInput.fromJson(Map<String, dynamic> json) => BashToolInput(
    command: json['command'] as String,
    timeoutMs: json['timeout'] as int?,
    description: json['description'] as String?,
    runInBackground: json['run_in_background'] as bool? ?? false,
    dangerouslyDisableSandbox:
        json['dangerouslyDisableSandbox'] as bool? ?? false,
  );
}

/// Bash tool output.
class BashToolOutput {
  final String stdout;
  final String stderr;
  final int exitCode;
  final bool interrupted;
  final bool isImage;
  final String? backgroundTaskId;
  final bool backgroundedByUser;
  final bool assistantAutoBackgrounded;
  final String? returnCodeInterpretation;
  final bool noOutputExpected;
  final String? persistedOutputPath;
  final int? persistedOutputSize;

  const BashToolOutput({
    required this.stdout,
    this.stderr = '',
    required this.exitCode,
    this.interrupted = false,
    this.isImage = false,
    this.backgroundTaskId,
    this.backgroundedByUser = false,
    this.assistantAutoBackgrounded = false,
    this.returnCodeInterpretation,
    this.noOutputExpected = false,
    this.persistedOutputPath,
    this.persistedOutputSize,
  });

  Map<String, dynamic> toJson() => {
    'stdout': stdout,
    'stderr': stderr,
    'exitCode': exitCode,
    if (interrupted) 'interrupted': true,
    if (isImage) 'isImage': true,
    if (backgroundTaskId != null) 'backgroundTaskId': backgroundTaskId,
    if (returnCodeInterpretation != null)
      'returnCodeInterpretation': returnCodeInterpretation,
    if (persistedOutputPath != null) 'persistedOutputPath': persistedOutputPath,
    if (persistedOutputSize != null) 'persistedOutputSize': persistedOutputSize,
  };
}

/// Semantic exit code interpretation.
String? interpretExitCode(String command, int exitCode) {
  if (exitCode == 0) return null;

  final baseCmd = command.trim().split(RegExp(r'\s+')).first;

  return switch (baseCmd) {
    'grep' ||
    'rg' ||
    'ag' ||
    'ack' when exitCode == 1 => 'No matches found (not an error)',
    'find' || 'fd' when exitCode == 1 =>
      'Partial results (some directories inaccessible)',
    'diff' when exitCode == 1 => 'Differences found (not an error)',
    'test' || '[' when exitCode == 1 => 'Condition evaluated to false',
    'curl' when exitCode == 6 => 'Could not resolve host',
    'curl' when exitCode == 7 => 'Failed to connect to host',
    'curl' when exitCode == 28 => 'Operation timed out',
    _ => null,
  };
}

/// Commands that are expected to produce no output.
const _silentCommands = {
  'mv',
  'cp',
  'rm',
  'mkdir',
  'rmdir',
  'chmod',
  'chown',
  'touch',
  'ln',
  'cd',
  'export',
  'unset',
  'source',
  '.',
};

/// Check if a command is expected to be silent.
bool isSilentCommand(String command) {
  final base = command.trim().split(RegExp(r'\s+')).first;
  return _silentCommands.contains(base);
}

/// Search/read/list classification for UI display.
({bool isSearch, bool isRead, bool isList}) classifyCommand(String command) {
  const searchCmds = {
    'find',
    'grep',
    'rg',
    'ag',
    'ack',
    'locate',
    'which',
    'whereis',
    'fd',
    'fzf',
  };
  const readCmds = {
    'cat',
    'head',
    'tail',
    'less',
    'more',
    'wc',
    'stat',
    'file',
    'strings',
    'jq',
    'yq',
    'awk',
    'cut',
    'sort',
    'uniq',
    'tr',
    'xxd',
    'hexdump',
    'od',
  };
  const listCmds = {'ls', 'tree', 'du', 'df', 'lsof', 'lsblk'};

  final segments = command.split(RegExp(r'\s*[|;&]\s*'));
  if (segments.isEmpty) {
    return (isSearch: false, isRead: false, isList: false);
  }

  var isSearch = true;
  var isRead = true;
  var isList = true;

  for (final seg in segments) {
    final base = seg.trim().split(RegExp(r'\s+')).first;
    if (base.isEmpty) continue;
    if (!searchCmds.contains(base)) isSearch = false;
    if (!readCmds.contains(base)) isRead = false;
    if (!listCmds.contains(base)) isList = false;
  }

  return (isSearch: isSearch, isRead: isRead, isList: isList);
}

// ── Security ──

/// Dangerous shell patterns that should be blocked or warned about.
class BashSecurityCheck {
  final String id;
  final String description;
  final bool Function(String command) check;
  final bool blocking;

  const BashSecurityCheck({
    required this.id,
    required this.description,
    required this.check,
    this.blocking = true,
  });
}

/// Result of security validation.
class SecurityCheckResult {
  final bool passed;
  final List<String> violations;
  final List<String> warnings;

  const SecurityCheckResult({
    required this.passed,
    this.violations = const [],
    this.warnings = const [],
  });
}

/// Dangerous zsh builtins.
const _dangerousZshBuiltins = {
  'zmodload',
  'emulate',
  'sysopen',
  'sysread',
  'syswrite',
  'sysseek',
  'zpty',
  'ztcp',
  'zsocket',
  'mapfile',
};

/// Patterns for command substitution.
final _commandSubstitutionPattern = RegExp(
  r'\$\(' // $( command substitution
  r'|\$\[' // $[ legacy arithmetic
  r'|\$\{' // ${ parameter expansion
  r'|<\(' // <( process substitution
  r'|>\(' // >( process substitution
  r'|=\(', // =( zsh process substitution
);

/// Dangerous git operations.
final _destructiveGitPatterns = RegExp(
  r'\bgit\s+(reset\s+--hard|push\s+--force|push\s+-f|clean\s+-f'
  r'|checkout\s+\.|restore\s+\.|stash\s+drop|branch\s+-D)\b',
);

/// Dangerous general operations.
final _destructivePatterns = RegExp(
  r'\brm\s+-rf\b|\brm\s+-r\b|\brm\s+-f\b'
  r'|\bDROP\s+TABLE\b|\bTRUNCATE\b|\bDELETE\s+FROM\b'
  r'|\bkubectl\s+delete\b|\bterraform\s+destroy\b',
  caseSensitive: false,
);

/// Validate a command for security issues.
SecurityCheckResult validateCommandSecurity(String command) {
  final violations = <String>[];
  final warnings = <String>[];

  final trimmed = command.trim();
  if (trimmed.isEmpty) {
    return const SecurityCheckResult(
      passed: false,
      violations: ['Empty command'],
    );
  }

  // Check for dangerous zsh builtins
  final baseCmd = trimmed.split(RegExp(r'\s+')).first;
  if (_dangerousZshBuiltins.contains(baseCmd)) {
    violations.add('Dangerous zsh builtin: $baseCmd');
  }

  // Check zf_ prefixed commands
  if (baseCmd.startsWith('zf_')) {
    violations.add('Dangerous zsh function: $baseCmd');
  }

  // Check for command substitution patterns
  if (_commandSubstitutionPattern.hasMatch(command)) {
    // Allow $() in single-quoted strings
    final inSingleQuote = _isInSingleQuotes(
      command,
      _commandSubstitutionPattern,
    );
    if (!inSingleQuote) {
      violations.add(
        'Command substitution detected — use explicit commands instead',
      );
    }
  }

  // Check for backticks
  if (_hasUnescapedBackticks(command)) {
    violations.add('Backtick command substitution — use \$() instead');
  }

  // Check for control characters
  if (RegExp(r'[\x00-\x08\x0e-\x1f]').hasMatch(command)) {
    violations.add('Control characters detected in command');
  }

  // Check destructive patterns (warnings, not blocking)
  if (_destructiveGitPatterns.hasMatch(command)) {
    warnings.add('Destructive git operation detected');
  }
  if (_destructivePatterns.hasMatch(command)) {
    warnings.add('Potentially destructive operation detected');
  }

  // Check for sleep > 2s (suggest background instead)
  final sleepMatch = RegExp(r'\bsleep\s+(\d+)').firstMatch(command);
  if (sleepMatch != null) {
    final seconds = int.tryParse(sleepMatch.group(1)!) ?? 0;
    if (seconds > 2) {
      warnings.add('Sleep > 2s — consider running in background');
    }
  }

  return SecurityCheckResult(
    passed: violations.isEmpty,
    violations: violations,
    warnings: warnings,
  );
}

bool _isInSingleQuotes(String command, RegExp pattern) {
  final match = pattern.firstMatch(command);
  if (match == null) return false;
  final beforeMatch = command.substring(0, match.start);
  var inSingle = false;
  for (var i = 0; i < beforeMatch.length; i++) {
    if (beforeMatch[i] == "'" && (i == 0 || beforeMatch[i - 1] != '\\')) {
      inSingle = !inSingle;
    }
  }
  return inSingle;
}

bool _hasUnescapedBackticks(String command) {
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < command.length; i++) {
    final c = command[i];
    if (c == "'" && !inDouble && (i == 0 || command[i - 1] != '\\')) {
      inSingle = !inSingle;
    } else if (c == '"' && !inSingle && (i == 0 || command[i - 1] != '\\')) {
      inDouble = !inDouble;
    } else if (c == '`' && !inSingle && (i == 0 || command[i - 1] != '\\')) {
      return true;
    }
  }
  return false;
}

// ── Path Validation ──

/// System paths that should never be deleted.
const _dangerousRemovalPaths = {
  '/', '/bin', '/sbin', '/usr', '/usr/bin', '/usr/sbin', '/usr/lib',
  '/usr/local', '/sys', '/etc', '/boot', '/dev', '/proc', '/home',
  '/root', '/var', '/tmp', '/lib', '/lib64', '/opt', '/mnt', '/media',
  '/srv', '/snap', '/run',
  // macOS specific
  '/System', '/Library', '/Applications', '/Users',
  // Windows-ish
  'C:\\', 'C:\\Windows', 'C:\\Program Files',
};

/// Framework paths that shouldn't be deleted entirely.
const _protectedFrameworkPaths = {
  'node_modules',
  '.git',
  'venv',
  '__pycache__',
  '.dart_tool',
  'build',
  '.gradle',
  'target',
  'vendor',
};

/// Dangerous config files that need extra permission.
const _dangerousFiles = {
  '.gitconfig',
  '.gitmodules',
  '.bashrc',
  '.bash_profile',
  '.zshrc',
  '.zprofile',
  '.profile',
  '.ripgreprc',
  '.mcp.json',
  '.neomage.json',
  '.npmrc',
  '.yarnrc',
  '.env',
  '.env.local',
  '.env.production',
};

/// Check if a command attempts dangerous path operations.
({bool isDangerous, String? reason}) checkPathSafety(String command) {
  // Check rm/rmdir commands
  final rmMatch = RegExp(
    r'\b(rm|rmdir)\s+((-[rfvd]+\s+)*)(.*)',
  ).firstMatch(command);

  if (rmMatch != null) {
    final path = rmMatch.group(4)?.trim() ?? '';

    // Check system paths
    for (final dangerous in _dangerousRemovalPaths) {
      if (path == dangerous || path.startsWith('$dangerous/')) {
        return (
          isDangerous: true,
          reason: 'Cannot remove system path: $dangerous',
        );
      }
    }

    // Check framework paths
    for (final framework in _protectedFrameworkPaths) {
      if (path == framework || path.endsWith('/$framework')) {
        return (
          isDangerous: true,
          reason: 'Removing framework directory: $framework',
        );
      }
    }
  }

  return (isDangerous: false, reason: null);
}

/// Check if a command targets a dangerous file.
bool targetsDangerousFile(String command, String filePath) {
  final fileName = filePath.split('/').last;
  return _dangerousFiles.contains(fileName);
}

// ── Read-Only Validation ──

/// Safe git subcommands for read-only mode.
const _safeGitSubcommands = {
  'log', 'show', 'diff', 'status', 'branch', 'tag', 'remote',
  'blame', 'rev-parse', 'rev-list', 'shortlog', 'describe',
  'ls-files', 'ls-tree', 'cat-file', 'name-rev', 'reflog',
  'stash', // only 'stash list' and 'stash show'
  'config', // only with --get, --list
  'worktree', // only 'worktree list'
};

/// Safe commands in read-only mode (commands that cannot execute arbitrary
/// subprograms or write files without explicit flags checked below).
const _readOnlySafeCommands = {
  // File inspection
  'cat', 'head', 'tail', 'less', 'more', 'wc', 'stat', 'file',
  'strings', 'xxd', 'hexdump', 'od', 'readlink', 'realpath',
  // Search
  'grep', 'rg', 'ag', 'ack', 'find', 'fd', 'locate', 'which',
  'whereis', 'type',
  // List
  'ls', 'tree', 'du', 'df', 'lsof',
  // Text processing (no file writing — 'tee' intentionally excluded!)
  'jq', 'yq', 'awk', 'cut', 'sort', 'uniq', 'tr',
  'sed', // only without -i / --in-place flag
  'column', 'paste', 'comm', 'diff', 'cmp',
  // System info ('env' and 'command' excluded — they execute arbitrary binaries)
  'uname', 'hostname', 'whoami', 'id', 'groups', 'date',
  'uptime', 'free', 'ps', 'top', 'htop', 'lscpu', 'nproc',
  'printenv', 'echo', 'printf', 'true', 'false',
  // Package / tool CLIs (strict subcommand allowlists enforced below)
  'npm', 'yarn', 'pnpm',
  'pip', 'pip3',
  'gem',
  'cargo',
  'docker',
  'gh',
};

const _readOnlyNodeSubcommands = {
  'list',
  'ls',
  'info',
  'view',
  'show',
  'why',
  'outdated',
  '--version',
  '-v',
};

const _readOnlyPipSubcommands = {
  'list',
  'show',
  'freeze',
  'check',
  '--version',
  '-V',
};

const _readOnlyGemSubcommands = {
  'list',
  'info',
  'specification',
  'environment',
  '--version',
  '-v',
};

/// Note: `cargo check` / `cargo clippy` are intentionally excluded from
/// read-only mode because `build.rs` executes arbitrary host code.
const _readOnlyCargoSubcommands = {
  '--version',
  '-V',
  'metadata',
  'tree',
  'pkgid',
  'verify-project',
};

const _readOnlyDockerSubcommands = {
  'ps',
  'images',
  'inspect',
  'logs',
  'version',
  'info',
  'stats',
};

const _readOnlyGhResources = {'pr', 'issue', 'repo', 'run', 'release', 'status'};
const _readOnlyGhActions = {'view', 'list', 'status', 'diff', 'checks'};

const _findDangerousFlags = {
  '-delete',
  '-exec',
  '-execdir',
  '-ok',
  '-okdir',
  '-fprint',
  '-fprint0',
  '-fprintf',
  '-fls',
};

/// Check if a command is safe in read-only mode.
({bool isSafe, String? reason}) isReadOnlyCommand(String command) {
  if (command.trim().isEmpty) {
    return (isSafe: false, reason: 'Empty command');
  }
  if (command.contains('\x00') ||
      command.contains('\n') ||
      command.contains('\r')) {
    return (
      isSafe: false,
      reason: 'Multiline or NUL-containing commands are not allowed in read-only mode',
    );
  }
  if (command.contains('`') ||
      command.contains(r'$(') ||
      command.contains('<(') ||
      command.contains('>(')) {
    return (
      isSafe: false,
      reason: 'Command/process substitution is not allowed in read-only mode',
    );
  }

  final segments = command.split(RegExp(r'\s*(?:\|\||&&|[|;&])\s*'));

  for (final seg in segments) {
    final trimmedSeg = seg.trim();
    if (trimmedSeg.isEmpty) continue;

    // Check output/read-write redirection before splitting args.
    if (trimmedSeg.contains('>') || trimmedSeg.contains('>>')) {
      return (
        isSafe: false,
        reason: 'Output redirection is not allowed in read-only mode',
      );
    }

    final rawParts = trimmedSeg.split(RegExp(r'\s+'));
    // Strip leading VAR=val assignments.
    var cmdIdx = 0;
    while (cmdIdx < rawParts.length &&
        RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(rawParts[cmdIdx])) {
      cmdIdx++;
    }
    if (cmdIdx >= rawParts.length) continue;

    final parts = rawParts.sublist(cmdIdx);
    final cmd = parts.first;

    if (cmd == 'git') {
      if (parts.length < 2) {
        return (isSafe: false, reason: 'Bare git command not allowed in read-only mode');
      }
      final subCmd = parts[1];
      if (!_safeGitSubcommands.contains(subCmd)) {
        return (
          isSafe: false,
          reason: 'git $subCmd is not allowed in read-only mode',
        );
      }
      final subArgs = parts.sublist(2);
      if (subCmd == 'stash' &&
          (subArgs.isEmpty ||
              (subArgs.first != 'list' && subArgs.first != 'show'))) {
        return (
          isSafe: false,
          reason: 'Only git stash list/show are allowed in read-only mode',
        );
      }
      if (subCmd == 'config' &&
          !subArgs.any(
            (a) =>
                a == '--get' ||
                a == '--get-all' ||
                a == '--get-regexp' ||
                a == '--list' ||
                a == '-l',
          )) {
        return (
          isSafe: false,
          reason: 'git config requires --get or --list in read-only mode',
        );
      }
      if (subCmd == 'worktree' &&
          (subArgs.isEmpty || subArgs.first != 'list')) {
        return (
          isSafe: false,
          reason: 'Only git worktree list is allowed in read-only mode',
        );
      }
      if ((subCmd == 'branch' || subCmd == 'tag') &&
          subArgs.any(
            (a) =>
                a == '-d' ||
                a == '-D' ||
                a == '--delete' ||
                a == '-m' ||
                a == '-M' ||
                a == '-f' ||
                a == '--force',
          )) {
        return (
          isSafe: false,
          reason: 'Mutating git $subCmd flags are not allowed in read-only mode',
        );
      }
      if (subCmd == 'remote' &&
          subArgs.isNotEmpty &&
          subArgs.first != '-v' &&
          subArgs.first != '--verbose' &&
          subArgs.first != 'show' &&
          subArgs.first != 'get-url') {
        return (
          isSafe: false,
          reason: 'Mutating git remote subcommand is not allowed in read-only mode',
        );
      }
      continue;
    }

    if (!_readOnlySafeCommands.contains(cmd)) {
      return (isSafe: false, reason: '$cmd is not allowed in read-only mode');
    }

    final args = parts.sublist(1);

    // Check sed in-place flags (-i, -i.bak, --in-place)
    if (cmd == 'sed' &&
        args.any(
          (a) =>
              a == '-i' ||
              a.startsWith('-i') ||
              a == '--in-place' ||
              a.startsWith('--in-place='),
        )) {
      return (
        isSafe: false,
        reason: 'sed -i (in-place edit) is not allowed in read-only mode',
      );
    }

    // Check find mutating / exec / file-writing primaries
    if (cmd == 'find' &&
        args.any((a) => _findDangerousFlags.contains(a.toLowerCase()))) {
      return (
        isSafe: false,
        reason: 'find with -delete/-exec/-ok/-fprint is not allowed in read-only mode',
      );
    }

    // Check awk system() execution
    if (cmd == 'awk' && trimmedSeg.contains('system(')) {
      return (
        isSafe: false,
        reason: 'awk system() is not allowed in read-only mode',
      );
    }

    // Check package & container CLI subcommand allowlists
    if (cmd == 'npm' || cmd == 'yarn' || cmd == 'pnpm') {
      final sub = args.isEmpty ? '' : args.first;
      if (!_readOnlyNodeSubcommands.contains(sub)) {
        return (
          isSafe: false,
          reason: '$cmd $sub is not allowed in read-only mode',
        );
      }
    } else if (cmd == 'pip' || cmd == 'pip3') {
      final sub = args.isEmpty ? '' : args.first;
      if (!_readOnlyPipSubcommands.contains(sub)) {
        return (
          isSafe: false,
          reason: '$cmd $sub is not allowed in read-only mode',
        );
      }
    } else if (cmd == 'gem') {
      final sub = args.isEmpty ? '' : args.first.toLowerCase();
      if (!_readOnlyGemSubcommands.contains(sub)) {
        return (
          isSafe: false,
          reason: 'gem $sub is not allowed in read-only mode',
        );
      }
    } else if (cmd == 'cargo') {
      final sub = args.isEmpty ? '' : args.first;
      if (!_readOnlyCargoSubcommands.contains(sub)) {
        return (
          isSafe: false,
          reason: 'cargo $sub is not allowed in read-only mode',
        );
      }
    } else if (cmd == 'docker') {
      final sub = args.isEmpty ? '' : args.first;
      if (!_readOnlyDockerSubcommands.contains(sub)) {
        return (
          isSafe: false,
          reason: 'docker $sub is not allowed in read-only mode',
        );
      }
    } else if (cmd == 'gh') {
      if (args.isEmpty || !_readOnlyGhResources.contains(args.first)) {
        return (
          isSafe: false,
          reason: 'gh subcommand is not allowed in read-only mode',
        );
      }
      if (args.first != 'status' &&
          (args.length < 2 || !_readOnlyGhActions.contains(args[1]))) {
        return (
          isSafe: false,
          reason: 'gh ${args.join(" ")} is not allowed in read-only mode',
        );
      }
    }
  }

  return (isSafe: true, reason: null);
}

// ── Sandbox ──

/// Sandbox configuration.
class SandboxConfig {
  final bool enabled;
  final List<String> readAllowPaths;
  final List<String> writeAllowPaths;
  final bool networkEnabled;
  final List<String> excludedCommands;

  const SandboxConfig({
    this.enabled = false,
    this.readAllowPaths = const [],
    this.writeAllowPaths = const [],
    this.networkEnabled = true,
    this.excludedCommands = const [],
  });
}

/// Check if a command should use sandbox.
bool shouldUseSandbox(String command, SandboxConfig config) {
  if (!config.enabled) return false;

  final baseCmd = command.trim().split(RegExp(r'\s+')).first;

  // Check excluded commands
  for (final excluded in config.excludedCommands) {
    if (excluded.endsWith(':*')) {
      // Prefix match: "docker:*" matches "docker" and "docker ..."
      final prefix = excluded.substring(0, excluded.length - 2);
      if (baseCmd == prefix) return false;
    } else if (excluded == baseCmd || excluded == command.trim()) {
      return false;
    }
  }

  return true;
}

// ── Output Processing ──

/// Maximum output length before truncation.
const maxOutputLength = 5 * 1024 * 1024; // 5MB

/// Maximum persisted output size.
const maxPersistedOutputSize = 64 * 1024 * 1024; // 64MB

/// Truncate command output if too long.
String truncateOutput(String output, {int maxLength = maxOutputLength}) {
  if (output.length <= maxLength) return output;

  final truncated = output.substring(0, maxLength);
  final remainingLines = output.substring(maxLength).split('\n').length;
  return '$truncated\n\n... [$remainingLines lines truncated] ...';
}

/// Strip empty leading/trailing lines (preserve internal whitespace).
String stripEmptyLines(String output) {
  final lines = output.split('\n');
  var start = 0;
  while (start < lines.length && lines[start].trim().isEmpty) {
    start++;
  }
  var end = lines.length;
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end).join('\n');
}

/// Strip ANSI escape sequences from text.
String stripAnsi(String text) {
  return text.replaceAll(
    RegExp(r'\x1B\[[0-9;]*[a-zA-Z]|\x1B\][^\x07]*\x07'),
    '',
  );
}

/// Detect if output contains a base64 data URI image.
bool isImageOutput(String output) {
  return output.trimLeft().startsWith('data:image/');
}

/// Extract comment label from first line of command.
String? extractCommentLabel(String command) {
  final firstLine = command.split('\n').first.trim();
  final match = RegExp(r'^#\s*(.+)$').firstMatch(firstLine);
  return match?.group(1)?.trim();
}

// ── Shell Execution ──

/// Shell execution options.
class ShellExecOptions {
  final String? workingDirectory;
  final Map<String, String>? environment;
  final Duration timeout;
  final int maxOutputBytes;
  final bool mergeStderr;
  final void Function(String)? onProgress;

  const ShellExecOptions({
    this.workingDirectory,
    this.environment,
    this.timeout = const Duration(seconds: 30),
    this.maxOutputBytes = maxOutputLength,
    this.mergeStderr = true,
    this.onProgress,
  });
}

/// Execute a shell command with full BashTool semantics.
Future<BashToolOutput> executeCommand(
  BashToolInput input, {
  ShellExecOptions options = const ShellExecOptions(),
  SandboxConfig sandbox = const SandboxConfig(),
}) async {
  // 1. Security validation
  final securityResult = validateCommandSecurity(input.command);
  if (!securityResult.passed) {
    return BashToolOutput(
      stdout: '',
      stderr: 'Security violation: ${securityResult.violations.join('; ')}',
      exitCode: -1,
    );
  }

  // 2. Path safety check
  final pathCheck = checkPathSafety(input.command);
  if (pathCheck.isDangerous) {
    return BashToolOutput(
      stdout: '',
      stderr: pathCheck.reason ?? 'Dangerous path operation',
      exitCode: -1,
    );
  }

  // 3. Determine timeout (clamped 1s..10m)
  final timeout = input.timeoutMs != null
      ? Duration(milliseconds: input.timeoutMs!.clamp(1000, 600000))
      : options.timeout;

  // 4. Build sanitized environment
  final env = <String, String>{
    ...NeomageNetworkGuard.sanitizeSubprocessEnv(options.environment),
    'NEOMAGECODE': '1', // Side-channel hint
    'TERM': 'dumb', // Disable terminal features
  };

  // 5. Execute
  final shell = Platform.isWindows
      ? 'cmd.exe'
      : Platform.environment['SHELL'] ?? '/bin/sh';
  final shellArgs = Platform.isWindows
      ? ['/c', input.command]
      : ['-c', input.command];

  try {
    final process = await Process.start(
      shell,
      shellArgs,
      workingDirectory: options.workingDirectory,
      environment: env,
    );

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    var totalBytes = 0;
    var stderrBytes = 0;
    var interrupted = false;

    // Capture output with size limiting
    final stdoutSub = process.stdout.transform(utf8.decoder).listen((chunk) {
      totalBytes += chunk.length;
      if (totalBytes <= options.maxOutputBytes) {
        stdoutBuf.write(chunk);
        options.onProgress?.call(chunk);
      }
    });

    final stderrSub = process.stderr.transform(utf8.decoder).listen((chunk) {
      if (options.mergeStderr) {
        totalBytes += chunk.length;
        if (totalBytes <= options.maxOutputBytes) {
          stdoutBuf.write(chunk);
        }
      } else {
        stderrBytes += chunk.length;
        if (stderrBytes <= options.maxOutputBytes) {
          stderrBuf.write(chunk);
        }
      }
    });

    // Wait with timeout
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      interrupted = true;
      process.kill(ProcessSignal.sigterm);
      await Future.delayed(const Duration(seconds: 2));
      process.kill(ProcessSignal.sigkill);
      exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }

    await stdoutSub.cancel();
    await stderrSub.cancel();

    var stdout = stdoutBuf.toString();
    final stderr = stderrBuf.toString();

    // Process output
    stdout = stripEmptyLines(stdout);

    if (totalBytes > options.maxOutputBytes) {
      stdout = truncateOutput(stdout, maxLength: options.maxOutputBytes);
    }

    // Check for image output
    final isImage = isImageOutput(stdout);

    // Semantic exit code
    final interpretation = interpretExitCode(input.command, exitCode);

    // Silent command check
    final noOutput = stdout.trim().isEmpty && isSilentCommand(input.command);

    return BashToolOutput(
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      interrupted: interrupted,
      isImage: isImage,
      returnCodeInterpretation: interpretation,
      noOutputExpected: noOutput,
    );
  } catch (e) {
    return BashToolOutput(stdout: '', stderr: e.toString(), exitCode: -1);
  }
}

// ── Permission Rule Matching ──

/// Check if a command matches a permission rule pattern.
bool matchesPermissionRule(String command, String rulePattern) {
  // Exact match
  if (command == rulePattern) return true;

  // Legacy prefix match: "npm:*" matches "npm" and "npm ..."
  if (rulePattern.endsWith(':*')) {
    final prefix = rulePattern.substring(0, rulePattern.length - 2);
    return command == prefix || command.startsWith('$prefix ');
  }

  // Wildcard match: "npm *" matches "npm install lodash"
  if (rulePattern.contains('*') && !rulePattern.endsWith(':*')) {
    final regexPattern = rulePattern
        .replaceAll(r'\*', '\x00') // Escape literal \*
        .replaceAllMapped(RegExp(r'[.+?^${}()|[\]\\]'), (m) => '\\${m[0]}')
        .replaceAll('*', '.*')
        .replaceAll('\x00', r'\*');

    // Make trailing args optional (e.g., "git" matches "git *")
    final trailingOptional = regexPattern.endsWith('.*')
        ? '${regexPattern.substring(0, regexPattern.length - 2)}(.*)?'
        : regexPattern;

    return RegExp('^$trailingOptional\$', dotAll: true).hasMatch(command);
  }

  return false;
}

/// Suggest a permission rule for a command.
String suggestPermissionRule(String command) {
  final lines = command.split('\n');

  // Multiline → use first line prefix
  if (lines.length > 1) {
    final firstLine = lines.first.trim();
    final words = firstLine.split(RegExp(r'\s+'));
    if (words.length >= 2) return '${words[0]} ${words[1]}*';
    return '${words[0]}*';
  }

  // Single line → 2-word prefix
  final words = command.trim().split(RegExp(r'\s+'));
  if (words.length >= 2) return '${words[0]} ${words[1]}';
  return words[0];
}

// ── CWD Tracking ──

/// Working directory tracker for shell sessions.
class CwdTracker {
  String _cwd;
  final String _projectRoot;
  final bool _maintainProjectDir;

  CwdTracker({
    required String initialCwd,
    required String projectRoot,
    bool maintainProjectDir = true,
  }) : _cwd = initialCwd,
       _projectRoot = projectRoot,
       _maintainProjectDir = maintainProjectDir;

  String get cwd => _cwd;

  /// Update CWD from command output.
  String? updateCwd(String newCwd) {
    if (_maintainProjectDir && !_isUnderProject(newCwd)) {
      final reason =
          'Shell cwd was reset to $_projectRoot '
          '(was: $newCwd, outside project)';
      _cwd = _projectRoot;
      return reason;
    }

    _cwd = newCwd;
    return null;
  }

  bool _isUnderProject(String path) {
    if (path.isEmpty ||
        path.contains('\x00') ||
        path.startsWith(r'\\') ||
        path.startsWith('//')) {
      return false;
    }
    final resolvedTarget = p.posix.normalize(
      path.replaceAll(r'\', '/'),
    );
    final resolvedRoot = p.posix.normalize(
      _projectRoot.replaceAll(r'\', '/'),
    );
    if (resolvedTarget == resolvedRoot) return true;
    final rootPrefix = resolvedRoot.endsWith('/')
        ? resolvedRoot
        : '$resolvedRoot/';
    return resolvedTarget.startsWith(rootPrefix);
  }
}

// ── Heredoc Analysis ──

/// Check if a heredoc is safe (delimiter is quoted/escaped).
bool isSafeHeredoc(String command) {
  final heredocMatch = RegExp(r'<<-?\s*(\S+)').firstMatch(command);
  if (heredocMatch == null) return true;

  final delimiter = heredocMatch.group(1)!;

  // Quoted delimiter is safe
  if (delimiter.startsWith("'") || delimiter.startsWith('"')) return true;

  // Escaped delimiter is safe
  if (delimiter.startsWith(r'\')) return true;

  // Unquoted delimiter allows variable substitution — potentially unsafe
  return false;
}

/// Extract the base command from a heredoc.
String? extractHeredocBaseCommand(String command) {
  final match = RegExp(r'^(\S+)').firstMatch(command.trim());
  return match?.group(1);
}

// ── Safe Wrapper Stripping ──

/// Safe command prefixes that can be stripped for permission checking.
/// (`env` is excluded because `env -S` / `env PATH=...` can hijack execution.)
const _safeWrappers = {'timeout', 'time', 'nice', 'nohup', 'stdbuf'};

/// Safe environment variables that don't affect binary resolution, config loading,
/// or compiler/linker behavior (`PATH`, `HOME`, `SHELL`, `GOFLAGS`, `RUSTFLAGS`
/// are intentionally excluded to prevent binary/config hijacking).
const _safeEnvVars = {
  'NODE_ENV',
  'LANG',
  'LC_ALL',
  'LC_CTYPE',
  'TERM',
  'TZ',
  'FORCE_COLOR',
  'NO_COLOR',
  'CI',
  'DEBIAN_FRONTEND',
  'PYTHONDONTWRITEBYTECODE',
};

/// Strip safe wrappers and env vars from a command for permission checking.
String stripSafeWrappers(String command) {
  var cmd = command.trim();

  // Strip leading env vars (FOO=bar command)
  while (true) {
    final envMatch = RegExp(r'^(\w+)=\S+\s+(.+)').firstMatch(cmd);
    if (envMatch == null) break;
    final varName = envMatch.group(1)!;
    if (!_safeEnvVars.contains(varName)) break;
    cmd = envMatch.group(2)!.trim();
  }

  // Strip safe wrappers
  while (true) {
    final parts = cmd.split(RegExp(r'\s+'));
    if (parts.isEmpty) break;
    if (!_safeWrappers.contains(parts.first)) break;

    // Skip flags of the wrapper command
    var i = 1;
    while (i < parts.length && parts[i].startsWith('-')) {
      i++;
      // Skip flag values for flags that take arguments
      if (i < parts.length && !parts[i].startsWith('-')) {
        i++;
      }
    }
    cmd = parts.sublist(i).join(' ').trim();
    if (cmd.isEmpty) break;
  }

  return cmd;
}

// ── File Descriptor Validation ──

/// Allowed file descriptors (stdin, stdout, stderr only).
const _allowedFds = {0, 1, 2};

/// Check if a command uses restricted file descriptors.
bool hasRestrictedFds(String command) {
  final fdPattern = RegExp(r'(\d+)([<>])');
  for (final match in fdPattern.allMatches(command)) {
    final fd = int.tryParse(match.group(1)!);
    if (fd != null && !_allowedFds.contains(fd)) {
      return true;
    }
  }

  // Check /dev/fd/N access
  if (RegExp(r'/dev/fd/[3-9]').hasMatch(command)) return true;

  return false;
}
