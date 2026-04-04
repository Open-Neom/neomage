// Ripgrep utilities — port of neom_claw/src/utils/ripgrep.ts.
// Ripgrep command building, execution, result parsing, streaming, and
// file counting. Adapted for Dart/Flutter with dart:io process management.

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:path/path.dart' as p;

// ─── Configuration ───────────────────────────────────────────────────────────

/// Ripgrep execution mode.
enum RipgrepMode {
  /// System-installed ripgrep (rg on PATH).
  system,

  /// Vendored/bundled ripgrep binary.
  builtin,

  /// Embedded within the application binary.
  embedded,
}

/// Configuration for how to invoke ripgrep.
class RipgrepConfig {
  final RipgrepMode mode;
  final String command;
  final List<String> args;
  final String? argv0;

  const RipgrepConfig({
    required this.mode,
    required this.command,
    this.args = const [],
    this.argv0,
  });
}

/// Maximum buffer size for ripgrep output (20MB).
/// Large monorepos can have 200k+ files.
const int kMaxBufferSize = 20000000;

/// Default timeout for ripgrep operations (20 seconds, 60 for WSL).
const int kDefaultTimeoutMs = 20000;
const int kWslTimeoutMs = 60000;

/// Cached ripgrep configuration singleton.
RipgrepConfig? _cachedConfig;

/// Get the ripgrep configuration. Determines whether to use system, builtin,
/// or embedded ripgrep. Memoized after first call.
RipgrepConfig getRipgrepConfig({
  bool? useSystemRipgrep,
  bool? isBundledMode,
  String? vendorRoot,
}) {
  if (_cachedConfig != null) return _cachedConfig!;

  final wantsSystem =
      useSystemRipgrep ?? _isEnvDefinedFalsy('USE_BUILTIN_RIPGREP');

  // Try system ripgrep if user wants it.
  if (wantsSystem) {
    final systemPath = _findExecutable('rg');
    if (systemPath != null) {
      _cachedConfig = const RipgrepConfig(
        mode: RipgrepMode.system,
        command: 'rg',
        args: [],
      );
      return _cachedConfig!;
    }
  }

  // In bundled (native) mode, ripgrep is statically compiled.
  if (isBundledMode == true) {
    _cachedConfig = RipgrepConfig(
      mode: RipgrepMode.embedded,
      command: Platform.resolvedExecutable,
      args: const ['--no-config'],
      argv0: 'rg',
    );
    return _cachedConfig!;
  }

  // Fall back to vendored binary.
  final rgRoot =
      vendorRoot ??
      p.join(p.dirname(Platform.resolvedExecutable), 'vendor', 'ripgrep');
  final platformDir = '${_getArch()}-${_getPlatformName()}';
  final rgBinary = Platform.isWindows ? 'rg.exe' : 'rg';
  final command = p.join(rgRoot, platformDir, rgBinary);

  _cachedConfig = RipgrepConfig(
    mode: RipgrepMode.builtin,
    command: command,
    args: const [],
  );
  return _cachedConfig!;
}

/// Reset the cached config (useful for testing).
void resetRipgrepConfig() {
  _cachedConfig = null;
}

/// Public accessor for ripgrep command components.
({String rgPath, List<String> rgArgs, String? argv0}) ripgrepCommand() {
  final config = getRipgrepConfig();
  return (rgPath: config.command, rgArgs: config.args, argv0: config.argv0);
}

// ─── Error types ─────────────────────────────────────────────────────────────

/// Custom error class for ripgrep timeouts. Allows callers to distinguish
/// between "no matches" and "timed out".
class RipgrepTimeoutError implements Exception {
  final String message;
  final List<String> partialResults;

  const RipgrepTimeoutError(this.message, this.partialResults);

  @override
  String toString() => 'RipgrepTimeoutError: $message';
}

/// Check if an error is EAGAIN (resource temporarily unavailable).
/// This happens in resource-constrained environments (Docker, CI) when
/// ripgrep tries to spawn too many threads.
bool _isEagainError(String stderr) {
  return stderr.contains('os error 11') ||
      stderr.contains('Resource temporarily unavailable');
}

// ─── Raw execution ───────────────────────────────────────────────────────────

/// Result of a raw ripgrep execution.
class _RipgrepRawResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final String? signal;

  const _RipgrepRawResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.signal,
  });
}

/// Execute ripgrep with the given arguments and target.
Future<_RipgrepRawResult> _ripGrepRaw(
  List<String> args,
  String target, {
  bool singleThread = false,
  Duration? timeout,
}) async {
  final (:rgPath, :rgArgs, :argv0) = ripgrepCommand();

  // Use single-threaded mode only if explicitly requested for retry.
  final threadArgs = singleThread ? ['-j', '1'] : <String>[];
  final fullArgs = [...rgArgs, ...threadArgs, ...args, target];

  // Allow timeout to be configured, otherwise use platform defaults.
  final effectiveTimeout =
      timeout ??
      Duration(milliseconds: _isWsl() ? kWslTimeoutMs : kDefaultTimeoutMs);

  final completer = Completer<_RipgrepRawResult>();

  try {
    final process = await Process.start(
      rgPath,
      fullArgs,
      environment: argv0 != null ? {'ARGV0': argv0} : null,
    );

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    bool stdoutTruncated = false;
    bool stderrTruncated = false;

    final stdoutSub = process.stdout
        .transform(const SystemEncoding().decoder)
        .listen((data) {
          if (!stdoutTruncated) {
            stdoutBuffer.write(data);
            if (stdoutBuffer.length > kMaxBufferSize) {
              stdoutTruncated = true;
            }
          }
        });

    final stderrSub = process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((data) {
          if (!stderrTruncated) {
            stderrBuffer.write(data);
            if (stderrBuffer.length > kMaxBufferSize) {
              stderrTruncated = true;
            }
          }
        });

    // Set up timeout.
    Timer? killTimer;
    Timer? forceKillTimer;
    String? signal;

    killTimer = Timer(effectiveTimeout, () {
      signal = 'SIGTERM';
      process.kill(ProcessSignal.sigterm);
      // Escalate to SIGKILL if SIGTERM doesn't work within 5 seconds.
      forceKillTimer = Timer(const Duration(seconds: 5), () {
        signal = 'SIGKILL';
        process.kill(ProcessSignal.sigkill);
      });
    });

    final exitCode = await process.exitCode;
    killTimer.cancel();
    forceKillTimer?.cancel();
    await stdoutSub.cancel();
    await stderrSub.cancel();

    completer.complete(
      _RipgrepRawResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
        signal: signal,
      ),
    );
  } catch (e) {
    if (!completer.isCompleted) {
      completer.completeError(e);
    }
  }

  return completer.future;
}

// ─── Streaming ───────────────────────────────────────────────────────────────

/// Stream lines from ripgrep as they arrive, calling [onLines] per stdout
/// chunk.
///
/// Unlike [ripGrep] which buffers the entire stdout, this flushes complete
/// lines as soon as each chunk arrives. Partial trailing lines are carried
/// across chunk boundaries.
///
/// Callers that want to stop early should cancel via the returned
/// subscription or use a timeout. No EAGAIN retry, no internal timeout,
/// stderr is ignored; interactive callers own recovery.
Future<void> ripGrepStream(
  List<String> args,
  String target, {
  required void Function(List<String> lines) onLines,
}) async {
  await _codesignRipgrepIfNecessary();
  final (:rgPath, :rgArgs, :argv0) = ripgrepCommand();

  final process = await Process.start(rgPath, [
    ...rgArgs,
    ...args,
    target,
  ], environment: argv0 != null ? {'ARGV0': argv0} : null);

  String remainder = '';
  await process.stdout.transform(const SystemEncoding().decoder).forEach((
    chunk,
  ) {
    final data = remainder + chunk;
    final lines = data.split('\n');
    remainder = lines.removeLast();
    if (lines.isNotEmpty) {
      onLines(lines.map(_stripCR).toList());
    }
  });

  // Flush remaining.
  if (remainder.isNotEmpty) {
    onLines([_stripCR(remainder)]);
  }

  final exitCode = await process.exitCode;
  if (exitCode != 0 && exitCode != 1) {
    throw Exception('ripgrep exited with code $exitCode');
  }
}

String _stripCR(String line) {
  return line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
}

// ─── Stream-count files ──────────────────────────────────────────────────────

/// Stream-count lines from `rg --files` without buffering stdout.
///
/// On large repos (e.g. 247k files, 16MB of paths), calling [ripGrep] just
/// to read `.length` materializes the full stdout string plus a 247k-element
/// array. This counts newline bytes per chunk instead; peak memory is one
/// stream chunk (~64KB).
Future<int> ripGrepFileCount(
  List<String> args,
  String target, {
  Duration? timeout,
}) async {
  await _codesignRipgrepIfNecessary();
  final (:rgPath, :rgArgs, :argv0) = ripgrepCommand();

  final process = await Process.start(rgPath, [
    ...rgArgs,
    ...args,
    target,
  ], environment: argv0 != null ? {'ARGV0': argv0} : null);

  int lines = 0;
  await process.stdout.forEach((chunk) {
    for (final byte in chunk) {
      if (byte == 0x0A) lines++; // '\n'
    }
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0 && exitCode != 1) {
    throw Exception('rg --files exited $exitCode');
  }
  return lines;
}

// ─── Main ripGrep function ───────────────────────────────────────────────────

/// Execute ripgrep with the given arguments and target directory/file.
/// Returns a list of matching lines.
///
/// Handles:
///   - EAGAIN retry with single-threaded mode
///   - Timeout with partial results
///   - Buffer overflow with partial results
///   - Critical errors (ENOENT, EACCES, EPERM)
Future<List<String>> ripGrep(
  List<String> args,
  String target, {
  Duration? timeout,
}) async {
  await _codesignRipgrepIfNecessary();

  // Test ripgrep on first use and cache the result (fire and forget).
  _testRipgrepOnFirstUse().catchError((_) {});

  return _ripGrepWithRetry(args, target, timeout: timeout, isRetry: false);
}

Future<List<String>> _ripGrepWithRetry(
  List<String> args,
  String target, {
  Duration? timeout,
  required bool isRetry,
}) async {
  final result = await _ripGrepRaw(
    args,
    target,
    singleThread: isRetry,
    timeout: timeout,
  );

  // Success case.
  if (result.exitCode == 0) {
    return _parseLines(result.stdout);
  }

  // Exit code 1 is normal "no matches".
  if (result.exitCode == 1) {
    return [];
  }

  // Critical errors that indicate ripgrep is broken.
  // These should be surfaced to the user rather than silently returning empty.
  const criticalSignals = ['ENOENT', 'EACCES', 'EPERM'];
  if (criticalSignals.any((s) => result.stderr.contains(s))) {
    throw Exception('Ripgrep critical error: ${result.stderr}');
  }

  // If we hit EAGAIN and haven't retried yet, retry with single-threaded mode.
  if (!isRetry && _isEagainError(result.stderr)) {
    return _ripGrepWithRetry(args, target, timeout: timeout, isRetry: true);
  }

  // For all other errors, try to return partial results if available.
  final hasOutput = result.stdout.trim().isNotEmpty;
  final isTimeout = result.signal == 'SIGTERM' || result.signal == 'SIGKILL';
  final isBufferOverflow = result.stdout.length >= kMaxBufferSize;

  List<String> lines = [];
  if (hasOutput) {
    lines = _parseLines(result.stdout);
    // Drop last line for timeouts and buffer overflow -- it may be incomplete.
    if (lines.isNotEmpty && (isTimeout || isBufferOverflow)) {
      lines = lines.sublist(0, lines.length - 1);
    }
  }

  // If we timed out with no results, throw an error so NeomClaw knows the
  // search didn't complete rather than thinking there were no matches.
  if (isTimeout && lines.isEmpty) {
    final timeoutSecs = _isWsl() ? 60 : 20;
    throw RipgrepTimeoutError(
      'Ripgrep search timed out after $timeoutSecs seconds. '
      'The search may have matched files but did not complete in time. '
      'Try searching a more specific path or pattern.',
      lines,
    );
  }

  return lines;
}

/// Parse stdout into lines, stripping CR and filtering blanks.
List<String> _parseLines(String stdout) {
  return stdout
      .trim()
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\r$'), ''))
      .where((line) => line.isNotEmpty)
      .toList();
}

// ─── File counting ───────────────────────────────────────────────────────────

/// Memoization cache for file counts.
final Map<String, int?> _fileCountCache = {};

/// Count files in a directory recursively using ripgrep and round to the
/// nearest power of 10 for privacy.
///
/// This is much more efficient than using native Dart methods for counting
/// files in large directories since it uses ripgrep's highly optimized file
/// traversal.
///
/// [dirPath] — Directory path to count files in.
/// [ignorePatterns] — Optional additional patterns to ignore (beyond .gitignore).
/// Returns approximate file count rounded to the nearest power of 10.
Future<int?> countFilesRoundedRg(
  String dirPath, {
  List<String> ignorePatterns = const [],
  Duration? timeout,
}) async {
  // Cache key includes ignore patterns.
  final cacheKey = '$dirPath|${ignorePatterns.join(',')}';
  if (_fileCountCache.containsKey(cacheKey)) {
    return _fileCountCache[cacheKey];
  }

  // Skip file counting if we're in the home directory to avoid triggering
  // macOS TCC permission dialogs for Desktop, Downloads, Documents, etc.
  final homeDir =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (p.equals(p.canonicalize(dirPath), p.canonicalize(homeDir))) {
    _fileCountCache[cacheKey] = null;
    return null;
  }

  try {
    // Build ripgrep arguments:
    // --files: List files that would be searched
    // --hidden: Search hidden files and directories
    final args = ['--files', '--hidden'];

    // Add ignore patterns if provided.
    for (final pattern in ignorePatterns) {
      args.addAll(['--glob', '!$pattern']);
    }

    final count = await ripGrepFileCount(args, dirPath, timeout: timeout);

    // Round to nearest power of 10 for privacy.
    if (count == 0) {
      _fileCountCache[cacheKey] = 0;
      return 0;
    }

    final magnitude = (log(count) / ln10).floor();
    final power = pow(10, magnitude).toInt();

    // Round to nearest power of 10.
    // e.g., 8 -> 10, 42 -> 100, 350 -> 100, 750 -> 1000
    final rounded = ((count / power).round()) * power;
    _fileCountCache[cacheKey] = rounded;
    return rounded;
  } catch (error) {
    // Timeout is expected on large/slow repos, not an error.
    _fileCountCache[cacheKey] = null;
    return null;
  }
}

/// Reset the file count cache (useful for testing).
void resetFileCountCache() {
  _fileCountCache.clear();
}

// ─── Status and testing ──────────────────────────────────────────────────────

/// Singleton to store ripgrep availability status.
class RipgrepStatus {
  final bool working;
  final int lastTested;
  final RipgrepConfig config;

  const RipgrepStatus({
    required this.working,
    required this.lastTested,
    required this.config,
  });
}

RipgrepStatus? _ripgrepStatus;

/// Get ripgrep status and configuration info.
/// Returns current configuration immediately, with working status if available.
({RipgrepMode mode, String path, bool? working}) getRipgrepStatus() {
  final config = getRipgrepConfig();
  return (
    mode: config.mode,
    path: config.command,
    working: _ripgrepStatus?.working,
  );
}

/// Test ripgrep availability. Memoized; only runs once.
bool _testStarted = false;

Future<void> _testRipgrepOnFirstUse() async {
  if (_ripgrepStatus != null || _testStarted) return;
  _testStarted = true;

  final config = getRipgrepConfig();

  try {
    final result = await Process.run(
      config.command,
      [...config.args, '--version'],
      environment: config.argv0 != null ? {'ARGV0': config.argv0!} : null,
    );

    final working =
        result.exitCode == 0 &&
        result.stdout is String &&
        (result.stdout as String).startsWith('ripgrep ');

    _ripgrepStatus = RipgrepStatus(
      working: working,
      lastTested: DateTime.now().millisecondsSinceEpoch,
      config: config,
    );
  } catch (_) {
    _ripgrepStatus = RipgrepStatus(
      working: false,
      lastTested: DateTime.now().millisecondsSinceEpoch,
      config: config,
    );
  }
}

// ─── Codesigning (macOS) ─────────────────────────────────────────────────────

bool _alreadyDoneSignCheck = false;

/// On macOS, vendored ripgrep binaries may need ad-hoc code signing and
/// quarantine attribute removal to run without Gatekeeper blocking.
Future<void> _codesignRipgrepIfNecessary() async {
  if (!Platform.isMacOS || _alreadyDoneSignCheck) return;
  _alreadyDoneSignCheck = true;

  // Only sign the standalone vendored rg binary (builtin mode).
  final config = getRipgrepConfig();
  if (config.mode != RipgrepMode.builtin) return;

  final builtinPath = config.command;

  // First, check to see if ripgrep is already signed.
  try {
    final checkResult = await Process.run('codesign', [
      '-vv',
      '-d',
      builtinPath,
    ]);
    final output = checkResult.stdout as String;
    final needsSigned = output.contains('linker-signed');
    if (!needsSigned) return;
  } catch (_) {
    return;
  }

  // Sign and remove quarantine attribute.
  try {
    final signResult = await Process.run('codesign', [
      '--sign',
      '-',
      '--force',
      '--preserve-metadata=entitlements,requirements,flags,runtime',
      builtinPath,
    ]);

    if (signResult.exitCode != 0) {
      // Log but don't throw -- ripgrep might still work.
    }

    await Process.run('xattr', ['-d', 'com.apple.quarantine', builtinPath]);
  } catch (_) {
    // Best effort.
  }
}

// ─── Platform helpers ────────────────────────────────────────────────────────

/// Check if an environment variable is defined and falsy (empty, '0', 'false').
bool _isEnvDefinedFalsy(String name) {
  final value = Platform.environment[name];
  if (value == null) return false;
  return value.isEmpty || value == '0' || value.toLowerCase() == 'false';
}

/// Find an executable on the system PATH.
String? _findExecutable(String name) {
  try {
    final result = Process.runSync(Platform.isWindows ? 'where' : 'which', [
      name,
    ]);
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim().split('\n').first;
      return path.isNotEmpty ? path : null;
    }
  } catch (_) {}
  return null;
}

/// Get the current platform architecture string.
String _getArch() {
  // Dart doesn't directly expose architecture, but we can infer it.
  // This is a simplified version.
  if (Platform.version.contains('arm64') ||
      Platform.version.contains('aarch64')) {
    return 'arm64';
  }
  return 'x64';
}

/// Get the platform name for directory lookup.
String _getPlatformName() {
  if (Platform.isWindows) return 'win32';
  if (Platform.isMacOS) return 'darwin';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

/// Detect if running under WSL (Windows Subsystem for Linux).
bool _isWsl() {
  if (!Platform.isLinux) return false;
  try {
    final release = File('/proc/version').readAsStringSync();
    return release.toLowerCase().contains('microsoft') ||
        release.toLowerCase().contains('wsl');
  } catch (_) {
    return false;
  }
}

/// Count occurrences of a character in a string or buffer.
int _countChar(List<int> data, int charCode) {
  int count = 0;
  for (final byte in data) {
    if (byte == charCode) count++;
  }
  return count;
}
