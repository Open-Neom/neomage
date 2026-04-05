import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/core/platform/shell_executor.dart';

import 'tool.dart';

/// Execute shell commands via neom_cli's CliExecutor.
/// Available on macOS, Linux, and Windows.
class BashTool extends Tool with ShellToolMixin {
  final Duration timeout;
  final String? workingDirectory;

  BashTool({this.timeout = const Duration(minutes: 2), this.workingDirectory});

  @override
  String get name => 'Bash';

  @override
  String get description =>
      'Executes a given bash command and returns its output.\n\n'
      'IMPORTANT: Avoid using this tool to run `find`, `grep`, `cat`, `head`, `tail`, `sed`, `awk`, or `echo` commands. '
      'Instead, use the appropriate dedicated tool:\n'
      '- File search: Use Glob (NOT find or ls)\n'
      '- Content search: Use Grep (NOT grep or rg)\n'
      '- Read files: Use Read (NOT cat/head/tail)\n'
      '- Edit files: Use Edit (NOT sed/awk)\n'
      '- Write files: Use Write (NOT echo >/cat <<EOF)\n\n'
      'Instructions:\n'
      '- If your command will create new directories or files, first run `ls` to verify the parent directory exists.\n'
      '- Always quote file paths that contain spaces.\n'
      '- Try to maintain your current working directory by using absolute paths.\n'
      '- When issuing multiple commands: if independent, make multiple Bash calls in parallel. '
      'If dependent, chain with && in a single call.\n'
      '- For git commands: prefer new commits over amending. Never skip hooks (--no-verify). '
      'Before destructive operations (git reset --hard, git push --force), consider safer alternatives.\n'
      '- Avoid unnecessary `sleep` commands — diagnose root causes instead of retry loops.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'command': {
        'type': 'string',
        'description': 'The bash command to execute',
      },
      'description': {
        'type': 'string',
        'description':
            'Clear, concise description of what this command does in active voice',
      },
      'timeout': {
        'type': 'integer',
        'description':
            'Optional timeout in milliseconds (up to 600000ms / 10 minutes). '
            'Default: 120000ms (2 minutes)',
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
    final effectiveTimeout = timeoutMs != null
        ? Duration(milliseconds: timeoutMs)
        : timeout;

    try {
      final result = await ShellExecutor.run(
        command,
        workingDirectory: workingDirectory,
        timeout: effectiveTimeout,
      );

      final stdout = result.stdout.trim();
      final stderr = result.stderr.trim();

      if (result.isTimeout) {
        return ToolResult.error(
          'Command timed out after ${effectiveTimeout.inSeconds}s',
        );
      }

      if (!result.isSuccess) {
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
    } on TimeoutException {
      return ToolResult.error(
        'Command timed out after ${effectiveTimeout.inSeconds}s',
      );
    } catch (e) {
      return ToolResult.error('Process error: $e');
    }
  }
}
