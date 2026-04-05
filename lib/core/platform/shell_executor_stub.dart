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

/// Web stub — shell execution is not available on web.
class ShellExecutor {
  static Future<ShellResult> run(
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    return const ShellResult(
      exitCode: -1,
      stdout: '',
      stderr: 'Shell execution not available on this platform',
    );
  }

  static Stream<String> stream(
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 120),
  }) {
    return Stream.value('Shell execution not available on this platform');
  }
}
