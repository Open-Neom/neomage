// PowerShellTool — execute PowerShell commands cross-platform.
// Uses pwsh (PowerShell Core) on macOS/Linux, powershell.exe on Windows.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

import 'tool.dart';

// ─── Input ───────────────────────────────────────────────────────────────────

/// Parsed input for PowerShell command execution.
class PowerShellInput {
  final String command;
  final String? workDir;
  final Duration timeout;
  final String? executionPolicy;

  const PowerShellInput({
    required this.command,
    this.workDir,
    this.timeout = const Duration(minutes: 2),
    this.executionPolicy,
  });

  factory PowerShellInput.fromMap(Map<String, dynamic> map) {
    final timeoutMs = map['timeout'] as num?;
    return PowerShellInput(
      command: map['command'] as String? ?? '',
      workDir:
          map['work_dir'] as String? ??
          map['working_directory'] as String? ??
          map['workDir'] as String?,
      timeout: timeoutMs != null
          ? Duration(milliseconds: timeoutMs.toInt())
          : const Duration(minutes: 2),
      executionPolicy: map['execution_policy'] as String?,
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (command.isEmpty) {
      errors.add('Missing required parameter: command');
    } else if (command.contains('\x00')) {
      errors.add('Invalid NUL byte in command');
    }
    if (workDir != null) {
      if (workDir!.contains('\x00')) {
        errors.add('Invalid NUL byte in work_dir');
      } else if (workDir!.startsWith(r'\\') || workDir!.startsWith('//')) {
        errors.add('UNC paths are not allowed for work_dir');
      }
    }
    if (executionPolicy != null &&
        !_validPolicies.contains(executionPolicy!.toLowerCase())) {
      errors.add(
        'execution_policy must be one of: ${_validPolicies.join(", ")}',
      );
    }
    if (timeout.inMilliseconds <= 0) {
      errors.add('timeout must be positive');
    }
    if (timeout.inMilliseconds > _maxTimeoutMs) {
      errors.add('timeout must not exceed ${_maxTimeoutMs ~/ 1000} seconds');
    }
    return errors;
  }

  static const _validPolicies = [
    'bypass',
    'restricted',
    'allsigned',
    'remotesigned',
    'unrestricted',
    'undefined',
  ];
  static const _maxTimeoutMs = 600000; // 10 minutes
}

// ─── Output ──────────────────────────────────────────────────────────────────

/// Result of a PowerShell command execution.
class PowerShellOutput {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  const PowerShellOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

  bool get isSuccess => exitCode == 0;

  Map<String, dynamic> toMetadata() => {
    'exitCode': exitCode,
    'durationMs': duration.inMilliseconds,
    'stdoutLength': stdout.length,
    'stderrLength': stderr.length,
  };

  @override
  String toString() {
    final buf = StringBuffer();
    if (stdout.isNotEmpty) buf.writeln(stdout);
    if (stderr.isNotEmpty) buf.writeln('STDERR: $stderr');
    buf.writeln('Exit code: $exitCode');
    buf.writeln('Duration: ${duration.inMilliseconds}ms');
    return buf.toString();
  }
}

// ─── Unsafe command patterns ─────────────────────────────────────────────────

/// Patterns that indicate potentially dangerous commands.
final _unsafePatterns = <RegExp>[
  // File system destructive operations.
  RegExp(r'Remove-Item\s+.*-Recurse', caseSensitive: false),
  RegExp(r'rm\s+-rf\s', caseSensitive: false),
  RegExp(r'Format-Volume', caseSensitive: false),
  RegExp(r'Clear-Disk', caseSensitive: false),
  // Registry modifications.
  RegExp(r'Remove-ItemProperty\s+.*HKLM', caseSensitive: false),
  RegExp(r'Set-ItemProperty\s+.*HKLM', caseSensitive: false),
  // System / security alteration.
  RegExp(r'Stop-Computer', caseSensitive: false),
  RegExp(r'Restart-Computer', caseSensitive: false),
  RegExp(r'Disable-NetAdapter', caseSensitive: false),
  RegExp(r'(?:Set|Add)-MpPreference\b', caseSensitive: false),
  // Credential exposure.
  RegExp(r'ConvertFrom-SecureString', caseSensitive: false),
  RegExp(r'Get-Credential.*Export', caseSensitive: false),
  // Base64 / encoded payload obfuscation (-e / -ec / -enc / -EncodedCommand).
  RegExp(
    r'(?:^|\s)-(?:e|ec|enc|encodedcommand)\b',
    caseSensitive: false,
  ),
  // Script download and execution cradles.
  RegExp(
    r'Invoke-Expression\s*\(\s*\(?\s*Invoke-WebRequest',
    caseSensitive: false,
  ),
  RegExp(r'iex\s*\(\s*irm\s', caseSensitive: false),
  RegExp(r'iex\s*\(\s*iwr\s', caseSensitive: false),
  RegExp(
    r'(?:Invoke-WebRequest|Invoke-RestMethod|iwr|irm)\b.*\|\s*(?:Invoke-Expression|iex)\b',
    caseSensitive: false,
  ),
  RegExp(
    r'(?:Net\.WebClient|DownloadString|DownloadFile|Start-BitsTransfer)',
    caseSensitive: false,
  ),
];

// ─── Tool ────────────────────────────────────────────────────────────────────

/// Execute PowerShell commands cross-platform.
///
/// Features:
/// - Cross-platform: uses `pwsh` on macOS/Linux, `powershell` on Windows
/// - Configurable execution policy
/// - Configurable timeout (default 2 min, max 10 min)
/// - Stdout and stderr capture
/// - Command safety checking for dangerous patterns
/// - Environment variable passthrough
/// - Full JSON Schema definition
class PowerShellTool extends Tool with ShellToolMixin {
  /// Default timeout for command execution.
  final Duration defaultTimeout;

  /// Default execution policy.
  final String? defaultExecutionPolicy;

  /// Working directory override.
  final String? workingDirectory;

  /// Additional environment variables to pass to the process.
  final Map<String, String>? environment;

  /// Whether to run command safety checks.
  final bool enableSafetyChecks;

  PowerShellTool({
    this.defaultTimeout = const Duration(minutes: 2),
    this.defaultExecutionPolicy,
    this.workingDirectory,
    this.environment,
    this.enableSafetyChecks = true,
  });

  @override
  String get name => 'PowerShell';

  @override
  String get description =>
      'Execute PowerShell commands. Uses pwsh (PowerShell Core) on macOS '
      'and Linux, powershell.exe on Windows. Supports configurable execution '
      'policy, timeout, and working directory.';

  @override
  String get prompt =>
      'Execute PowerShell commands cross-platform.\n\n'
      'On macOS/Linux, uses pwsh (PowerShell Core). On Windows, uses '
      'powershell.exe.\n'
      'Supports execution policy configuration, timeouts (max 10 min), '
      'and working directory.\n'
      'Certain dangerous commands are blocked by default for safety.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'command': {
        'type': 'string',
        'description': 'The PowerShell command to execute',
      },
      'work_dir': {
        'type': 'string',
        'description':
            'Working directory for command execution. '
            'Uses current directory if not specified.',
      },
      'timeout': {
        'type': 'number',
        'description':
            'Timeout in milliseconds (max 600000 / 10 minutes). '
            'Default is 120000 (2 minutes).',
      },
      'execution_policy': {
        'type': 'string',
        'enum': [
          'Bypass',
          'Restricted',
          'AllSigned',
          'RemoteSigned',
          'Unrestricted',
          'Undefined',
        ],
        'description':
            'PowerShell execution policy for this command. '
            'Default depends on system configuration.',
      },
    },
    'required': ['command'],
    'additionalProperties': false,
  };

  @override
  bool get isAvailable => _findPowerShell() != null;

  @override
  bool get shouldDefer => true;

  @override
  bool get alwaysLoad => false;

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final cmd = input['command'] as String? ?? '';
    final truncated = cmd.length > 60 ? '${cmd.substring(0, 57)}...' : cmd;
    return 'PowerShell: $truncated';
  }

  @override
  String getActivityDescription(Map<String, dynamic> input) =>
      'Executing PowerShell command';

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final parsed = PowerShellInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) {
      return ValidationResult.invalid(errors.first);
    }
    if (enableSafetyChecks) {
      final safetyError = _checkCommandSafety(parsed.command);
      if (safetyError != null) {
        return ValidationResult.invalid(safetyError);
      }
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = PowerShellInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) {
      return ToolResult.error(errors.join('; '));
    }

    // Safety check.
    if (enableSafetyChecks) {
      final safetyError = _checkCommandSafety(parsed.command);
      if (safetyError != null) {
        return ToolResult.error(safetyError);
      }
    }

    // Resolve the PowerShell executable.
    final executable = _findPowerShell();
    if (executable == null) {
      return ToolResult.error(
        'PowerShell not found. Install PowerShell Core (pwsh) from '
        'https://github.com/PowerShell/PowerShell',
      );
    }

    // Build arguments.
    final args = <String>[];
    final policy = parsed.executionPolicy ?? defaultExecutionPolicy;
    if (policy != null) {
      args.addAll(['-ExecutionPolicy', policy]);
    }
    args.addAll(['-NoProfile', '-NonInteractive', '-Command', parsed.command]);

    // Resolve working directory.
    final effectiveWorkDir = parsed.workDir ?? workingDirectory;
    if (effectiveWorkDir != null &&
        (effectiveWorkDir.contains('\x00') ||
            effectiveWorkDir.startsWith(r'\\') ||
            effectiveWorkDir.startsWith('//'))) {
      return ToolResult.error('Unsafe working directory rejected');
    }

    // Build sanitized environment.
    final effectiveEnv = NeomageNetworkGuard.sanitizeSubprocessEnv({
      ...Platform.environment,
      ...?environment,
    });

    // Execute with Process.start + bounded streams + child termination on timeout.
    const maxStreamBytes = 4 * 1024 * 1024;
    final stopwatch = Stopwatch()..start();

    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: effectiveWorkDir,
        environment: effectiveEnv,
        includeParentEnvironment: false,
      );

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      var stdoutBytes = 0;
      var stderrBytes = 0;

      final stdoutSub = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
            if (stdoutBytes < maxStreamBytes) {
              final rem = maxStreamBytes - stdoutBytes;
              stdoutBuf.write(
                chunk.length <= rem ? chunk : chunk.substring(0, rem),
              );
            }
            stdoutBytes += chunk.length;
          });

      final stderrSub = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((chunk) {
            if (stderrBytes < maxStreamBytes) {
              final rem = maxStreamBytes - stderrBytes;
              stderrBuf.write(
                chunk.length <= rem ? chunk : chunk.substring(0, rem),
              );
            }
            stderrBytes += chunk.length;
          });

      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(parsed.timeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigterm);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        process.kill(ProcessSignal.sigkill);
        await stdoutSub.cancel();
        await stderrSub.cancel();
        stopwatch.stop();
        return ToolResult.error(
          'PowerShell command timed out after '
          '${parsed.timeout.inSeconds}s',
        );
      }

      await stdoutSub.cancel();
      await stderrSub.cancel();
      stopwatch.stop();

      final output = PowerShellOutput(
        exitCode: exitCode,
        stdout: stdoutBuf.toString().trim(),
        stderr: stderrBuf.toString().trim(),
        duration: stopwatch.elapsed,
      );

      if (!output.isSuccess) {
        return ToolResult(
          content: output.toString(),
          isError: true,
          metadata: output.toMetadata(),
        );
      }

      return ToolResult.success(
        output.toString(),
        metadata: output.toMetadata(),
      );
    } on ProcessException catch (e) {
      stopwatch.stop();
      return ToolResult.error('PowerShell process error: ${e.message}');
    } catch (e) {
      stopwatch.stop();
      return ToolResult.error('PowerShell execution error: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Find the PowerShell executable for the current platform.
  static String? _findPowerShell() {
    if (Platform.isWindows) {
      // Prefer PowerShell Core, fall back to Windows PowerShell.
      for (final exe in ['pwsh.exe', 'powershell.exe']) {
        if (_isExecutableAvailable(exe)) return exe;
      }
      return null;
    }
    // macOS / Linux — only PowerShell Core.
    if (_isExecutableAvailable('pwsh')) return 'pwsh';
    return null;
  }

  /// Check if an executable is available on PATH.
  static bool _isExecutableAvailable(String name) {
    try {
      final result = Platform.isWindows
          ? Process.runSync('where', [name])
          : Process.runSync('which', [name]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Check a command for dangerous patterns. Returns an error message or null.
  String? _checkCommandSafety(String command) {
    for (final pattern in _unsafePatterns) {
      if (pattern.hasMatch(command)) {
        return 'Command blocked by safety check: potentially dangerous '
            'pattern detected (${pattern.pattern}). '
            'Review the command and run it manually if intended.';
      }
    }
    return null;
  }
}
