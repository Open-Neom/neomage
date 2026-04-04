// BashTool full — port of neom_claw/src/tools/BashTool/.
// Complete shell command execution with security, sandboxing, output handling.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'tool.dart';

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
        if (persistedOutputPath != null)
          'persistedOutputPath': persistedOutputPath,
        if (persistedOutputSize != null)
          'persistedOutputSize': persistedOutputSize,
      };
}

/// Semantic exit code interpretation.
String? interpretExitCode(String command, int exitCode) {
  if (exitCode == 0) return null;

  final baseCmd = command.trim().split(RegExp(r'\s+')).first;

  return switch (baseCmd) {
    'grep' || 'rg' || 'ag' || 'ack' when exitCode == 1 =>
      'No matches found (not an error)',
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
  'mv', 'cp', 'rm', 'mkdir', 'rmdir', 'chmod', 'chown',
  'touch', 'ln', 'cd', 'export', 'unset', 'source', '.',
};

/// Check if a command is expected to be silent.
bool isSilentCommand(String command) {
  final base = command.trim().split(RegExp(r'\s+')).first;
  return _silentCommands.contains(base);
}

/// Search/read/list classification for UI display.
({bool isSearch, bool isRead, bool isList}) classifyCommand(String command) {
  const searchCmds = {
    'find', 'grep', 'rg', 'ag', 'ack', 'locate', 'which', 'whereis',
    'fd', 'fzf',
  };
  const readCmds = {
    'cat', 'head', 'tail', 'less', 'more', 'wc', 'stat', 'file',
    'strings', 'jq', 'yq', 'awk', 'cut', 'sort', 'uniq', 'tr',
    'xxd', 'hexdump', 'od',
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
  'zmodload', 'emulate', 'sysopen', 'sysread', 'syswrite', 'sysseek',
  'zpty', 'ztcp', 'zsocket', 'mapfile',
};

/// Patterns for command substitution.
final _commandSubstitutionPattern = RegExp(
  r'\$\('         // $( command substitution
  r'|\$\['        // $[ legacy arithmetic
  r'|\$\{'        // ${ parameter expansion
  r'|<\('         // <( process substitution
  r'|>\('         // >( process substitution
  r'|=\('         // =( zsh process substitution
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
    final inSingleQuote = _isInSingleQuotes(command, _commandSubstitutionPattern);
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
  'node_modules', '.git', 'venv', '__pycache__', '.dart_tool',
  'build', '.gradle', 'target', 'vendor',
};

/// Dangerous config files that need extra permission.
const _dangerousFiles = {
  '.gitconfig', '.gitmodules', '.bashrc', '.bash_profile', '.zshrc',
  '.zprofile', '.profile', '.ripgreprc', '.mcp.json', '.neomclaw.json',
  '.npmrc', '.yarnrc', '.env', '.env.local', '.env.production',
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

/// Safe commands in read-only mode.
const _readOnlySafeCommands = {
  // File inspection
  'cat', 'head', 'tail', 'less', 'more', 'wc', 'stat', 'file',
  'strings', 'xxd', 'hexdump', 'od', 'readlink', 'realpath',
  // Search
  'grep', 'rg', 'ag', 'ack', 'find', 'fd', 'locate', 'which',
  'whereis', 'type', 'command',
  // List
  'ls', 'tree', 'du', 'df', 'lsof',
  // Text processing (no file writing)
  'jq', 'yq', 'awk', 'cut', 'sort', 'uniq', 'tr', 'tee',
  'sed', // only without -i flag
  'column', 'paste', 'comm', 'diff', 'cmp',
  // System info
  'uname', 'hostname', 'whoami', 'id', 'groups', 'date',
  'uptime', 'free', 'ps', 'top', 'htop', 'lscpu', 'nproc',
  'env', 'printenv', 'echo', 'printf', 'true', 'false',
  // Package info (read-only)
  'npm', 'yarn', 'pnpm', // only list/info subcommands
  'pip', 'pip3', // only list/show/freeze
  'gem', // only list/info
  'cargo', // only check/clippy
  // Docker (read-only)
  'docker', // only inspect/images/ps/logs
  // GitHub CLI (read-only)
  'gh', // only view/list/comment
};

/// Check if a command is safe in read-only mode.
({bool isSafe, String? reason}) isReadOnlyCommand(String command) {
  final segments = command.split(RegExp(r'\s*[|;&]\s*'));

  for (final seg in segments) {
    final parts = seg.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) continue;

    final base = parts.first;

    // Strip env var prefixes (FOO=bar command)
    var cmd = base;
    if (cmd.contains('=')) {
      final remaining = parts.sublist(1);
      if (remaining.isEmpty) continue;
      cmd = remaining.first;
    }

    if (!_readOnlySafeCommands.contains(cmd) &&
        !_safeGitSubcommands.contains(cmd)) {
      // Check git subcommand
      if (cmd == 'git' && parts.length > 1) {
        final subCmd = parts[1];
        if (!_safeGitSubcommands.contains(subCmd)) {
          return (
            isSafe: false,
            reason: 'git $subCmd is not allowed in read-only mode',
          );
        }
      } else {
        return (
          isSafe: false,
          reason: '$cmd is not allowed in read-only mode',
        );
      }
    }

    // Check sed -i (in-place edit)
    if (cmd == 'sed' && (parts.contains('-i') || parts.contains('-i.bak'))) {
      return (
        isSafe: false,
        reason: 'sed -i (in-place edit) is not allowed in read-only mode',
      );
    }

    // Check output redirection
    if (seg.contains('>') || seg.contains('>>')) {
      return (
        isSafe: false,
        reason: 'Output redirection is not allowed in read-only mode',
      );
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

  // 3. Determine timeout
  final timeout = input.timeoutMs != null
      ? Duration(milliseconds: input.timeoutMs!)
      : options.timeout;

  // 4. Build environment
  final env = <String, String>{
    ...?options.environment,
    'NEOMCLAWCODE': '1', // Side-channel hint
    'TERM': 'dumb',    // Disable terminal features
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
        stderrBuf.write(chunk);
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
    final interpretation =
        interpretExitCode(input.command, exitCode);

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
    return BashToolOutput(
      stdout: '',
      stderr: e.toString(),
      exitCode: -1,
    );
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
  })  : _cwd = initialCwd,
        _projectRoot = projectRoot,
        _maintainProjectDir = maintainProjectDir;

  String get cwd => _cwd;

  /// Update CWD from command output.
  String? updateCwd(String newCwd) {
    if (_maintainProjectDir && !_isUnderProject(newCwd)) {
      final reason = 'Shell cwd was reset to $_projectRoot '
          '(was: $newCwd, outside project)';
      _cwd = _projectRoot;
      return reason;
    }

    _cwd = newCwd;
    return null;
  }

  bool _isUnderProject(String path) {
    final normalized = path.endsWith('/') ? path : '$path/';
    final projectNorm =
        _projectRoot.endsWith('/') ? _projectRoot : '$_projectRoot/';
    return normalized.startsWith(projectNorm) || path == _projectRoot;
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
const _safeWrappers = {
  'timeout', 'time', 'nice', 'nohup', 'stdbuf', 'env',
};

/// Safe environment variables that don't affect security.
const _safeEnvVars = {
  'NODE_ENV', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TERM', 'TZ',
  'FORCE_COLOR', 'NO_COLOR', 'CI', 'DEBIAN_FRONTEND',
  'PYTHONDONTWRITEBYTECODE', 'GOFLAGS', 'RUSTFLAGS',
  'HOME', 'PATH', 'SHELL', 'USER', 'LOGNAME',
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
