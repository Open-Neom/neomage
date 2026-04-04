/// Process management utilities.
///
/// Provides structured process execution, pooling, piped commands,
/// parallel execution, and shell introspection.
library;

import 'dart:async';
import 'dart:collection';
import 'package:neom_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Configuration for running a process.
class ProcessConfig {
  final String command;
  final List<String> args;
  final String? workDir;
  final Map<String, String>? env;
  final Duration? timeout;
  final String? stdin;
  final bool captureStdout;
  final bool captureStderr;
  final bool runInShell;

  const ProcessConfig({
    required this.command,
    this.args = const [],
    this.workDir,
    this.env,
    this.timeout,
    this.stdin,
    this.captureStdout = true,
    this.captureStderr = true,
    this.runInShell = false,
  });

  /// Full command string for display purposes.
  String get fullCommand => '$command ${args.join(' ')}'.trim();

  @override
  String toString() => 'ProcessConfig($fullCommand)';
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

/// The result of running a process.
class ProcessOutput {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;
  final int pid;
  final bool killed;

  const ProcessOutput({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    required this.duration,
    required this.pid,
    this.killed = false,
  });

  /// Whether the process exited successfully (exit code 0).
  bool get isSuccess => exitCode == 0;

  @override
  String toString() =>
      'ProcessOutput(exit=$exitCode, pid=$pid, duration=${duration.inMilliseconds}ms)';
}

// ---------------------------------------------------------------------------
// Process info
// ---------------------------------------------------------------------------

/// Status of a tracked process.
enum ProcessStatus { running, exited, killed }

/// Information about a running or completed process.
class ProcessInfo {
  final int pid;
  final String command;
  final DateTime startTime;
  ProcessStatus status;

  ProcessInfo({
    required this.pid,
    required this.command,
    required this.startTime,
    this.status = ProcessStatus.running,
  });

  Duration get uptime => DateTime.now().difference(startTime);

  @override
  String toString() => 'ProcessInfo(pid=$pid, cmd=$command, status=$status)';
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/// Events emitted during process execution.
sealed class ProcessEvent {
  final int pid;
  const ProcessEvent(this.pid);
}

/// Emitted when a process starts.
class ProcessStarted extends ProcessEvent {
  final String command;
  const ProcessStarted(super.pid, this.command);
}

/// Emitted when stdout data is received.
class StdoutData extends ProcessEvent {
  final String data;
  const StdoutData(super.pid, this.data);
}

/// Emitted when stderr data is received.
class StderrData extends ProcessEvent {
  final String data;
  const StderrData(super.pid, this.data);
}

/// Emitted when a process exits.
class ProcessExited extends ProcessEvent {
  final int exitCode;
  const ProcessExited(super.pid, this.exitCode);
}

// ---------------------------------------------------------------------------
// ProcessManager
// ---------------------------------------------------------------------------

/// Manages process execution, tracking, and lifecycle.
class ProcessManager {
  final Map<int, Process> _processes = {};
  final Map<int, ProcessInfo> _processInfo = {};
  final StreamController<ProcessEvent> _eventController =
      StreamController<ProcessEvent>.broadcast();

  /// Stream of process events.
  Stream<ProcessEvent> get onOutput => _eventController.stream;

  /// Run a process and wait for it to complete.
  Future<ProcessOutput> run(ProcessConfig config) async {
    final sw = Stopwatch()..start();
    final process = await Process.start(
      config.command,
      config.args,
      workingDirectory: config.workDir,
      environment: config.env,
      runInShell: config.runInShell,
    );

    final pid = process.pid;
    _processes[pid] = process;
    _processInfo[pid] = ProcessInfo(
      pid: pid,
      command: config.fullCommand,
      startTime: DateTime.now(),
    );
    _eventController.add(ProcessStarted(pid, config.fullCommand));

    // Send stdin if provided
    if (config.stdin != null) {
      process.stdin.write(config.stdin);
      await process.stdin.close();
    }

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();

    final stdoutSub = process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((data) {
          if (config.captureStdout) stdoutBuf.write(data);
          _eventController.add(StdoutData(pid, data));
        });

    final stderrSub = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((data) {
          if (config.captureStderr) stderrBuf.write(data);
          _eventController.add(StderrData(pid, data));
        });

    int exitCode;
    var killed = false;

    if (config.timeout != null) {
      exitCode = await process.exitCode.timeout(
        config.timeout!,
        onTimeout: () {
          process.kill(ProcessSignal.sigterm);
          killed = true;
          return -1;
        },
      );
    } else {
      exitCode = await process.exitCode;
    }

    await stdoutSub.cancel();
    await stderrSub.cancel();
    sw.stop();

    _processInfo[pid]?.status = killed
        ? ProcessStatus.killed
        : ProcessStatus.exited;
    _processes.remove(pid);
    _eventController.add(ProcessExited(pid, exitCode));

    return ProcessOutput(
      exitCode: exitCode,
      stdout: stdoutBuf.toString(),
      stderr: stderrBuf.toString(),
      duration: sw.elapsed,
      pid: pid,
      killed: killed,
    );
  }

  /// Start an interactive process (returns the raw [Process]).
  Future<Process> runInteractive(ProcessConfig config) async {
    final process = await Process.start(
      config.command,
      config.args,
      workingDirectory: config.workDir,
      environment: config.env,
      runInShell: config.runInShell,
      mode: ProcessStartMode.inheritStdio,
    );

    final pid = process.pid;
    _processes[pid] = process;
    _processInfo[pid] = ProcessInfo(
      pid: pid,
      command: config.fullCommand,
      startTime: DateTime.now(),
    );
    _eventController.add(ProcessStarted(pid, config.fullCommand));

    // Track exit
    process.exitCode.then((code) {
      _processInfo[pid]?.status = ProcessStatus.exited;
      _processes.remove(pid);
      _eventController.add(ProcessExited(pid, code));
    });

    return process;
  }

  /// Run a process with an explicit timeout.
  Future<ProcessOutput> runWithTimeout(ProcessConfig config, Duration timeout) {
    return run(
      ProcessConfig(
        command: config.command,
        args: config.args,
        workDir: config.workDir,
        env: config.env,
        timeout: timeout,
        stdin: config.stdin,
        captureStdout: config.captureStdout,
        captureStderr: config.captureStderr,
        runInShell: config.runInShell,
      ),
    );
  }

  /// Pipe stdout of each process into stdin of the next.
  Future<ProcessOutput> runPiped(List<ProcessConfig> configs) async {
    if (configs.isEmpty) {
      return ProcessOutput(exitCode: 0, duration: Duration.zero, pid: 0);
    }
    if (configs.length == 1) return run(configs.first);

    final sw = Stopwatch()..start();
    var input = '';

    // If the first config has stdin, use it
    if (configs.first.stdin != null) {
      input = configs.first.stdin!;
    }

    ProcessOutput? lastOutput;
    for (var i = 0; i < configs.length; i++) {
      final cfg = ProcessConfig(
        command: configs[i].command,
        args: configs[i].args,
        workDir: configs[i].workDir,
        env: configs[i].env,
        timeout: configs[i].timeout,
        stdin: i == 0 ? configs[i].stdin : input,
        captureStdout: true,
        captureStderr: configs[i].captureStderr,
        runInShell: configs[i].runInShell,
      );
      lastOutput = await run(cfg);
      if (lastOutput.exitCode != 0) {
        sw.stop();
        return ProcessOutput(
          exitCode: lastOutput.exitCode,
          stdout: lastOutput.stdout,
          stderr: lastOutput.stderr,
          duration: sw.elapsed,
          pid: lastOutput.pid,
          killed: lastOutput.killed,
        );
      }
      input = lastOutput.stdout;
    }
    sw.stop();

    return ProcessOutput(
      exitCode: lastOutput!.exitCode,
      stdout: lastOutput.stdout,
      stderr: lastOutput.stderr,
      duration: sw.elapsed,
      pid: lastOutput.pid,
    );
  }

  /// Run multiple processes in parallel with optional concurrency limit.
  Future<List<ProcessOutput>> runParallel(
    List<ProcessConfig> configs, {
    int? maxConcurrency,
  }) async {
    if (maxConcurrency == null || maxConcurrency >= configs.length) {
      return Future.wait(configs.map(run));
    }

    final results = List<ProcessOutput?>.filled(configs.length, null);
    final pool = ProcessPool(maxConcurrency: maxConcurrency, manager: this);

    final futures = <Future<void>>[];
    for (var i = 0; i < configs.length; i++) {
      final idx = i;
      futures.add(pool.submit(configs[idx]).then((r) => results[idx] = r));
    }
    await Future.wait(futures);
    await pool.close();
    return results.cast<ProcessOutput>();
  }

  /// Kill a process by PID.
  bool kill(int pid, {ProcessSignal signal = ProcessSignal.sigterm}) {
    final process = _processes[pid];
    if (process == null) return false;
    _processInfo[pid]?.status = ProcessStatus.killed;
    return process.kill(signal);
  }

  /// Kill all tracked processes.
  void killAll({ProcessSignal signal = ProcessSignal.sigterm}) {
    for (final entry in _processes.entries.toList()) {
      entry.value.kill(signal);
      _processInfo[entry.key]?.status = ProcessStatus.killed;
    }
  }

  /// Check if a process is running.
  bool isRunning(int pid) => _processes.containsKey(pid);

  /// Get info about all tracked processes.
  List<ProcessInfo> getRunningProcesses() {
    return _processInfo.values
        .where((p) => p.status == ProcessStatus.running)
        .toList();
  }

  /// Dispose of resources.
  void dispose() {
    killAll();
    _eventController.close();
  }
}

// ---------------------------------------------------------------------------
// ProcessPool
// ---------------------------------------------------------------------------

/// A pool that limits concurrent process execution.
class ProcessPool {
  final int maxConcurrency;
  final ProcessManager _manager;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue();
  bool _closed = false;

  ProcessPool({required this.maxConcurrency, ProcessManager? manager})
    : _manager = manager ?? ProcessManager();

  /// Submit a process config for execution.
  ///
  /// If the pool is at capacity, this will wait until a slot opens.
  Future<ProcessOutput> submit(ProcessConfig config) async {
    await _acquire();
    try {
      return await _manager.run(config);
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrency) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  void _release() {
    _active--;
    if (_waiters.isNotEmpty) {
      _active++;
      _waiters.removeFirst().complete();
    }
  }

  /// Number of currently active processes.
  int get activeCount => _active;

  /// Number of queued processes waiting for a slot.
  int get queueLength => _waiters.length;

  /// Close the pool. No new submissions will be accepted.
  Future<void> close() async {
    _closed = true;
    // Drain remaining waiters
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    }
  }

  /// Whether the pool is closed.
  bool get isClosed => _closed;
}

// ---------------------------------------------------------------------------
// Shell utilities
// ---------------------------------------------------------------------------

/// Utilities for shell detection and command inspection.
class Shell {
  const Shell._();

  /// Detect the current user's shell.
  static String detectShell() {
    // Check SHELL env var
    final shell = Platform.environment['SHELL'];
    if (shell != null && shell.isNotEmpty) {
      return shell.split('/').last;
    }
    // Fallback for Windows
    final comspec = Platform.environment['COMSPEC'];
    if (comspec != null) {
      return comspec.split(Platform.pathSeparator).last;
    }
    return Platform.isWindows ? 'cmd.exe' : 'sh';
  }

  /// Get the path to the shell configuration file.
  static String getShellConfig() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    final shell = detectShell();
    return switch (shell) {
      'zsh' => '$home/.zshrc',
      'bash' => '$home/.bashrc',
      'fish' => '$home/.config/fish/config.fish',
      _ => '$home/.profile',
    };
  }

  /// Expand environment variables in [text].
  ///
  /// Replaces `$VAR` and `${VAR}` with values from [env] or the current
  /// platform environment.
  static String expandVariables(String text, [Map<String, String>? env]) {
    final environment = env ?? Platform.environment;
    var result = text;

    // ${VAR} form
    result = result.replaceAllMapped(
      RegExp(r'\$\{([^}]+)\}'),
      (m) => environment[m.group(1)] ?? m.group(0)!,
    );

    // $VAR form (must not be followed by another word char)
    result = result.replaceAllMapped(
      RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)'),
      (m) => environment[m.group(1)] ?? m.group(0)!,
    );

    return result;
  }

  /// Find the full path to a command using `which` (or `where` on Windows).
  static Future<String?> which(String command) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, [command]);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim().split('\n').first;
      }
    } catch (_) {}
    return null;
  }

  /// Get the current PATH as a list of directories.
  static List<String> getPath() {
    final pathVar = Platform.environment['PATH'] ?? '';
    final sep = Platform.isWindows ? ';' : ':';
    return pathVar.split(sep).where((p) => p.isNotEmpty).toList();
  }

  /// Basic safety check for a command string.
  ///
  /// Returns false if the command contains potentially dangerous patterns
  /// like `rm -rf /`, `mkfs`, `dd`, or writing to system paths.
  static bool isCommandSafe(String command) {
    final dangerous = [
      RegExp(r'\brm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+)?/\s'),
      RegExp(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f?[a-zA-Z]*\s+/\b'),
      RegExp(r'\bmkfs\b'),
      RegExp(r'\bdd\s+.*of=/dev/'),
      RegExp(r'>\s*/dev/[sh]d[a-z]'),
      RegExp(r'\bformat\s+[A-Z]:'),
      RegExp(r'\bchmod\s+(-[a-zA-Z]*\s+)?777\s+/'),
      RegExp(r'\bchown\s+.*\s+/'),
      RegExp(r':\(\)\s*\{\s*:\|:\s*&\s*\}\s*;'), // fork bomb
    ];
    for (final pattern in dangerous) {
      if (pattern.hasMatch(command)) return false;
    }
    return true;
  }

  /// Quote an argument for safe shell inclusion.
  static String quoteArg(String arg) {
    if (arg.isEmpty) return "''";
    if (Platform.isWindows) {
      // Windows quoting
      if (!arg.contains(RegExp(r'[\s"&|<>^%]'))) return arg;
      return '"${arg.replaceAll('"', '\\"')}"';
    }
    // POSIX
    if (RegExp(r'^[a-zA-Z0-9._/=:@-]+$').hasMatch(arg)) return arg;
    return "'${arg.replaceAll("'", "'\\''")}'";
  }
}
