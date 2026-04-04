// Process utilities — port of neom_claw process management.
// Process spawning, output capture, timeout handling.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

/// Result of a process execution.
class ProcessOutput {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration elapsed;
  final bool timedOut;

  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.elapsed,
    this.timedOut = false,
  });

  bool get success => exitCode == 0;
  String get combined => '$stdout$stderr';
}

/// Run a command and capture output.
Future<ProcessOutput> runCommand(
  String command,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration? timeout,
  int? maxOutputBytes,
}) async {
  final sw = Stopwatch()..start();

  try {
    final process = await Process.start(
      command,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    var stdoutBytes = 0;
    var stderrBytes = 0;

    final stdoutSub = process.stdout.transform(utf8.decoder).listen((chunk) {
      stdoutBytes += chunk.length;
      if (maxOutputBytes == null || stdoutBytes <= maxOutputBytes) {
        stdoutBuf.write(chunk);
      }
    });

    final stderrSub = process.stderr.transform(utf8.decoder).listen((chunk) {
      stderrBytes += chunk.length;
      if (maxOutputBytes == null || stderrBytes <= maxOutputBytes) {
        stderrBuf.write(chunk);
      }
    });

    int exitCode;
    bool timedOut = false;

    if (timeout != null) {
      final exitFuture = process.exitCode;
      final result = await Future.any([
        exitFuture,
        Future.delayed(timeout, () => -1),
      ]);

      if (result == -1) {
        timedOut = true;
        process.kill(ProcessSignal.sigterm);
        await Future.delayed(const Duration(seconds: 2));
        process.kill(ProcessSignal.sigkill);
        exitCode = await exitFuture.timeout(
          const Duration(seconds: 3),
          onTimeout: () => -1,
        );
      } else {
        exitCode = result;
      }
    } else {
      exitCode = await process.exitCode;
    }

    await stdoutSub.cancel();
    await stderrSub.cancel();
    sw.stop();

    var stdout = stdoutBuf.toString();
    var stderr = stderrBuf.toString();

    if (maxOutputBytes != null && stdoutBytes > maxOutputBytes) {
      stdout += '\n[... output truncated at $maxOutputBytes bytes]';
    }
    if (maxOutputBytes != null && stderrBytes > maxOutputBytes) {
      stderr += '\n[... output truncated at $maxOutputBytes bytes]';
    }

    return ProcessOutput(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      elapsed: sw.elapsed,
      timedOut: timedOut,
    );
  } catch (e) {
    sw.stop();
    return ProcessOutput(
      exitCode: -1,
      stdout: '',
      stderr: e.toString(),
      elapsed: sw.elapsed,
    );
  }
}

/// Run a shell command (via /bin/sh or cmd.exe).
Future<ProcessOutput> runShell(
  String command, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration? timeout,
  int? maxOutputBytes,
}) async {
  if (Platform.isWindows) {
    return runCommand(
      'cmd.exe',
      ['/c', command],
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
      maxOutputBytes: maxOutputBytes,
    );
  }

  return runCommand(
    '/bin/sh',
    ['-c', command],
    workingDirectory: workingDirectory,
    environment: environment,
    timeout: timeout,
    maxOutputBytes: maxOutputBytes,
  );
}

/// Spawn a long-running process with streaming output.
Future<ManagedProcess> spawnProcess(
  String command,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    command,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );

  return ManagedProcess._(process);
}

/// A managed process with streaming I/O.
class ManagedProcess {
  final Process _process;
  final StreamController<String> _stdoutController =
      StreamController.broadcast();
  final StreamController<String> _stderrController =
      StreamController.broadcast();
  late final StreamSubscription<String> _stdoutSub;
  late final StreamSubscription<String> _stderrSub;

  ManagedProcess._(this._process) {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .listen(_stdoutController.add);
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .listen(_stderrController.add);
  }

  /// PID of the process.
  int get pid => _process.pid;

  /// Stdout stream.
  Stream<String> get stdout => _stdoutController.stream;

  /// Stderr stream.
  Stream<String> get stderr => _stderrController.stream;

  /// Write to stdin.
  void write(String data) => _process.stdin.write(data);

  /// Write line to stdin.
  void writeln(String data) => _process.stdin.writeln(data);

  /// Close stdin.
  Future<void> closeStdin() => _process.stdin.close();

  /// Kill the process.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);

  /// Wait for exit.
  Future<int> get exitCode => _process.exitCode;

  /// Graceful shutdown: SIGTERM, wait, then SIGKILL.
  Future<int> shutdown({Duration grace = const Duration(seconds: 5)}) async {
    _process.kill(ProcessSignal.sigterm);

    final code = await _process.exitCode
        .timeout(grace, onTimeout: () {
      _process.kill(ProcessSignal.sigkill);
      return -1;
    });

    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    await _stdoutController.close();
    await _stderrController.close();

    return code;
  }
}

/// Check if a command is available on PATH.
Future<bool> commandExists(String command) async {
  try {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      [command],
    );
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
