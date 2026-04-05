import 'package:neom_cli/neom_cli.dart';

/// Result of a shell command execution.
class ShellResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration? duration;

  const ShellResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.duration,
  });

  bool get isSuccess => exitCode == 0;
  bool get isTimeout => exitCode == -2;
}

/// Desktop shell executor — delegates to neom_cli's [CliExecutor].
class ShellExecutor {
  static Future<ShellResult> run(
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    final result = await CliExecutor.run(
      command,
      workingDirectory: workingDirectory,
      timeout: timeout,
      environment: environment,
    );
    return ShellResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      duration: result.duration,
    );
  }

  /// Stream real-time output line-by-line.
  static Stream<String> stream(
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 120),
  }) {
    return CliExecutor().stream(
      command,
      config: ExecutionConfig(
        workingDirectory: workingDirectory,
        timeout: timeout,
      ),
    );
  }
}
