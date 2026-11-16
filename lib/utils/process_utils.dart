// Process utilities — port of neomage process management.
// Process spawning, output capture, timeout handling.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

/// Default cap (`16 MiB`) per stream when `maxOutputBytes` is omitted.
const int defaultMaxProcessOutputBytes = 16 * 1024 * 1024;

void _assertSafeProcessArgs(
  String command,
  List<String> args,
  String? workingDirectory,
) {
  if (command.isEmpty || command.contains('\x00')) {
    throw ArgumentError.value(command, 'command', 'Invalid executable');
  }
  for (final arg in args) {
    if (arg.contains('\x00')) {
      throw ArgumentError('Process argument contains NUL byte');
    }
  }
  if (workingDirectory != null) {
    if (workingDirectory.contains('\x00') ||
        workingDirectory.startsWith('//') ||
        workingDirectory.startsWith(r'\\')) {
      throw ArgumentError.value(
        workingDirectory,
        'workingDirectory',
        'Unsafe working directory',
      );
    }
  }
}

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
  final effectiveMaxBytes = maxOutputBytes ?? defaultMaxProcessOutputBytes;

  try {
    _assertSafeProcessArgs(command, args, workingDirectory);
    final process = await Process.start(
      command,
      args,
      workingDirectory: workingDirectory,
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(null, environment),
      includeParentEnvironment: false,
    );

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    var stdoutBytes = 0;
    var stderrBytes = 0;

    final stdoutSub = process.stdout.transform(utf8.decoder).listen((chunk) {
      stdoutBytes += chunk.length;
      if (stdoutBytes <= effectiveMaxBytes) {
        stdoutBuf.write(chunk);
      } else if (stdoutBuf.length < effectiveMaxBytes) {
        stdoutBuf.write(
          chunk.substring(0, effectiveMaxBytes - stdoutBuf.length),
        );
      }
    });

    final stderrSub = process.stderr.transform(utf8.decoder).listen((chunk) {
      stderrBytes += chunk.length;
      if (stderrBytes <= effectiveMaxBytes) {
        stderrBuf.write(chunk);
      } else if (stderrBuf.length < effectiveMaxBytes) {
        stderrBuf.write(
          chunk.substring(0, effectiveMaxBytes - stderrBuf.length),
        );
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

    if (stdoutBytes > effectiveMaxBytes) {
      stdout += '\n[... output truncated at $effectiveMaxBytes bytes]';
    }
    if (stderrBytes > effectiveMaxBytes) {
      stderr += '\n[... output truncated at $effectiveMaxBytes bytes]';
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
  _assertSafeProcessArgs(command, args, workingDirectory);
  final process = await Process.start(
    command,
    args,
    workingDirectory: workingDirectory,
    runInShell: false,
    environment: NeomageNetworkGuard.sanitizeSubprocessEnv(null, environment),
    includeParentEnvironment: false,
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
        .cast<String>()
        .listen(_stdoutController.add);
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .cast<String>()
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

    final code = await _process.exitCode.timeout(
      grace,
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );

    await _stdoutSub.cancel();
    await _stderrSub.cancel();
    await _stdoutController.close();
    await _stderrController.close();

    return code;
  }
}

/// Check if a command is available on PATH.
Future<bool> commandExists(String command) async {
  if (command.isEmpty ||
      command.startsWith('-') ||
      !RegExp(r'^[A-Za-z0-9._+-]{1,128}$').hasMatch(command)) {
    return false;
  }
  try {
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      [command],
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
      includeParentEnvironment: false,
    ).timeout(const Duration(seconds: 5));
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
