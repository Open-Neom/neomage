import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'tool.dart';

/// Execute shell commands — port of neom_claw/src/tools/BashTool.
/// Available on macOS, Linux, and Windows (via PowerShell).
class BashTool extends Tool with ShellToolMixin {
  final Duration timeout;
  final String? workingDirectory;

  BashTool({
    this.timeout = const Duration(minutes: 2),
    this.workingDirectory,
  });

  @override
  String get name => 'Bash';

  @override
  String get description =>
      'Executes a shell command and returns its output. '
      'Use for running scripts, installing packages, git operations, '
      'and other system tasks.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The shell command to execute',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Optional timeout in milliseconds',
          },
        },
        'required': ['command'],
      };

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final command = input['command'] as String?;
    if (command == null || command.isEmpty) {
      return ToolResult.error('Missing required parameter: command');
    }

    final timeoutMs = input['timeout'] as int?;
    final effectiveTimeout =
        timeoutMs != null ? Duration(milliseconds: timeoutMs) : timeout;

    try {
      final ProcessResult result;

      if (Platform.isWindows) {
        result = await Process.run(
          'powershell',
          ['-Command', command],
          workingDirectory: workingDirectory,
        ).timeout(effectiveTimeout);
      } else {
        result = await Process.run(
          '/bin/bash',
          ['-c', command],
          workingDirectory: workingDirectory,
        ).timeout(effectiveTimeout);
      }

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();

      if (result.exitCode != 0) {
        final output = [
          if (stdout.isNotEmpty) stdout,
          if (stderr.isNotEmpty) 'STDERR: $stderr',
          'Exit code: ${result.exitCode}',
        ].join('\n');
        return ToolResult(content: output, isError: true);
      }

      return ToolResult.success(
        [stdout, if (stderr.isNotEmpty) 'STDERR: $stderr'].join('\n'),
      );
    } on ProcessException catch (e) {
      return ToolResult.error('Process error: ${e.message}');
    } on TimeoutException {
      return ToolResult.error(
          'Command timed out after ${effectiveTimeout.inSeconds}s');
    }
  }
}
