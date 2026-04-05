// Cleanup manager — port of neomage cleanup.ts + gracefulShutdown.ts +
// backgroundHousekeeping.ts.
// Session/file cleanup, graceful shutdown coordination, and background
// housekeeping operations.

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════
// Part 1 — Cleanup types and helpers (from cleanup.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Default cleanup period in days.
const int defaultCleanupPeriodDays = 30;

/// One day in milliseconds.
const int _oneDayMs = 24 * 60 * 60 * 1000;

/// Result of a cleanup operation.
class CleanupResult {
  const CleanupResult({this.messages = 0, this.errors = 0});

  final int messages;
  final int errors;

  CleanupResult operator +(CleanupResult other) {
    return CleanupResult(
      messages: messages + other.messages,
      errors: errors + other.errors,
    );
  }

  @override
  String toString() => 'CleanupResult(messages: $messages, errors: $errors)';
}

/// Add two cleanup results together.
CleanupResult addCleanupResults(CleanupResult a, CleanupResult b) {
  return a + b;
}

/// Callback type for retrieving settings.
typedef SettingsProvider = Map<String, dynamic>? Function();

/// Callback type for checking raw settings key existence.
typedef RawSettingsContainsKeyFn = bool Function(String key);

// ── Configuration ──

/// Global settings provider (can be overridden for testing).
SettingsProvider _settingsProvider = () => null;

/// Set the settings provider callback.
void setCleanupSettingsProvider(SettingsProvider provider) {
  _settingsProvider = provider;
}

/// Global raw-settings key checker for validation-error guard.
RawSettingsContainsKeyFn _rawSettingsContainsKey = (_) => false;

/// Set the raw settings key check function.
void setRawSettingsContainsKey(RawSettingsContainsKeyFn fn) {
  _rawSettingsContainsKey = fn;
}

/// Compute the cutoff date from settings.
DateTime getCutoffDate() {
  final settings = _settingsProvider() ?? {};
  final cleanupPeriodDays =
      (settings['cleanupPeriodDays'] as int?) ?? defaultCleanupPeriodDays;
  final cleanupPeriodMs = cleanupPeriodDays * 24 * 60 * 60 * 1000;
  return DateTime.now().subtract(Duration(milliseconds: cleanupPeriodMs));
}

/// Convert a filename to a [DateTime] by parsing the ISO-like name.
/// Filenames use `-` in place of `:` and `.` in ISO timestamps.
DateTime convertFileNameToDate(String filename) {
  final baseName = filename.split('.').first;
  final isoStr = baseName.replaceAllMapped(
    RegExp(r'T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z'),
    (m) => 'T${m[1]}:${m[2]}:${m[3]}.${m[4]}Z',
  );
  return DateTime.parse(isoStr);
}

/// Get the Neomage config home directory.
String _getNeomageConfigHomeDir() {
  return Platform.environment['MAGE_CONFIG_HOME'] ??
      p.join(Platform.environment['HOME'] ?? '.', '.neomage');
}

/// Get the projects directory for session storage.
String _getProjectsDir() {
  return p.join(_getNeomageConfigHomeDir(), 'projects');
}

/// Get the base logs / cache directory.
String _getBaseLogsDir() {
  return p.join(_getNeomageConfigHomeDir(), 'logs');
}

/// Get the errors directory.
String _getErrorsDir() {
  return p.join(_getBaseLogsDir(), 'errors');
}

/// Tool results subdirectory name.
const String _toolResultsSubdir = 'tool-results';

// ── File cleanup operations ──

/// Clean up old files in a directory by comparing timestamps in filenames.
Future<CleanupResult> _cleanupOldFilesInDirectory(
  String dirPath,
  DateTime cutoffDate, {
  required bool isMessagePath,
}) async {
  var result = const CleanupResult();
  try {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return result;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final timestamp = convertFileNameToDate(p.basename(entity.path));
        if (timestamp.isBefore(cutoffDate)) {
          await entity.delete();
          result = CleanupResult(
            messages: result.messages + (isMessagePath ? 1 : 0),
            errors: result.errors + (isMessagePath ? 0 : 1),
          );
        }
      } catch (_) {
        // Log but continue processing other files.
      }
    }
  } on PathNotFoundException {
    // Ignore if directory doesn't exist.
  } catch (_) {}

  return result;
}

/// Unlink a file if its mtime is before cutoffDate. Returns `true` if removed.
Future<bool> _unlinkIfOld(String filePath, DateTime cutoffDate) async {
  final stat = await FileStat.stat(filePath);
  if (stat.modified.isBefore(cutoffDate)) {
    await File(filePath).delete();
    return true;
  }
  return false;
}

/// Attempt to remove an empty directory.
Future<void> _tryRmdir(String dirPath) async {
  try {
    await Directory(dirPath).delete();
  } catch (_) {
    // Not empty / doesn't exist.
  }
}

/// Clean up old message and error log files.
Future<CleanupResult> cleanupOldMessageFiles() async {
  final cutoffDate = getCutoffDate();
  final errorPath = _getErrorsDir();
  final baseCachePath = _getBaseLogsDir();

  var result = await _cleanupOldFilesInDirectory(
    errorPath,
    cutoffDate,
    isMessagePath: false,
  );

  // Clean up MCP logs.
  try {
    final baseDir = Directory(baseCachePath);
    if (!await baseDir.exists()) return result;

    await for (final entity in baseDir.list()) {
      if (entity is Directory &&
          p.basename(entity.path).startsWith('mcp-logs-')) {
        result =
            result +
            await _cleanupOldFilesInDirectory(
              entity.path,
              cutoffDate,
              isMessagePath: true,
            );
        await _tryRmdir(entity.path);
      }
    }
  } on PathNotFoundException {
    // Ignore.
  } catch (_) {}

  return result;
}

/// Clean up old session files (transcripts, tool results, etc.).
Future<CleanupResult> cleanupOldSessionFiles() async {
  final cutoffDate = getCutoffDate();
  var result = const CleanupResult();
  final projectsDir = _getProjectsDir();

  Directory projectsDirObj;
  try {
    projectsDirObj = Directory(projectsDir);
    if (!await projectsDirObj.exists()) return result;
  } catch (_) {
    return result;
  }

  await for (final projectDirent in projectsDirObj.list()) {
    if (projectDirent is! Directory) continue;
    final projectDir = projectDirent.path;

    List<FileSystemEntity> entries;
    try {
      entries = await Directory(projectDir).list().toList();
    } catch (_) {
      result = CleanupResult(
        messages: result.messages,
        errors: result.errors + 1,
      );
      continue;
    }

    for (final entry in entries) {
      if (entry is File) {
        final name = p.basename(entry.path);
        if (!name.endsWith('.jsonl') && !name.endsWith('.cast')) continue;
        try {
          if (await _unlinkIfOld(entry.path, cutoffDate)) {
            result = CleanupResult(
              messages: result.messages + 1,
              errors: result.errors,
            );
          }
        } catch (_) {
          result = CleanupResult(
            messages: result.messages,
            errors: result.errors + 1,
          );
        }
      } else if (entry is Directory) {
        // Session directory — clean up tool-results subdirs.
        final sessionDir = entry.path;
        final toolResultsDir = p.join(sessionDir, _toolResultsSubdir);

        List<FileSystemEntity> toolDirs;
        try {
          toolDirs = await Directory(toolResultsDir).list().toList();
        } catch (_) {
          await _tryRmdir(sessionDir);
          continue;
        }

        for (final toolEntry in toolDirs) {
          if (toolEntry is File) {
            try {
              if (await _unlinkIfOld(toolEntry.path, cutoffDate)) {
                result = CleanupResult(
                  messages: result.messages + 1,
                  errors: result.errors,
                );
              }
            } catch (_) {
              result = CleanupResult(
                messages: result.messages,
                errors: result.errors + 1,
              );
            }
          } else if (toolEntry is Directory) {
            final toolDirPath = toolEntry.path;
            List<FileSystemEntity> toolFiles;
            try {
              toolFiles = await Directory(toolDirPath).list().toList();
            } catch (_) {
              continue;
            }
            for (final tf in toolFiles) {
              if (tf is! File) continue;
              try {
                if (await _unlinkIfOld(tf.path, cutoffDate)) {
                  result = CleanupResult(
                    messages: result.messages + 1,
                    errors: result.errors,
                  );
                }
              } catch (_) {
                result = CleanupResult(
                  messages: result.messages,
                  errors: result.errors + 1,
                );
              }
            }
            await _tryRmdir(toolDirPath);
          }
        }
        await _tryRmdir(toolResultsDir);
        await _tryRmdir(sessionDir);
      }
    }

    await _tryRmdir(projectDir);
  }

  return result;
}

/// Generic helper for cleaning up old files in a single directory.
Future<CleanupResult> _cleanupSingleDirectory(
  String dirPath,
  String extension, {
  bool removeEmptyDir = true,
}) async {
  final cutoffDate = getCutoffDate();
  var result = const CleanupResult();

  List<FileSystemEntity> dirents;
  try {
    dirents = await Directory(dirPath).list().toList();
  } catch (_) {
    return result;
  }

  for (final dirent in dirents) {
    if (dirent is! File || !p.basename(dirent.path).endsWith(extension)) {
      continue;
    }
    try {
      if (await _unlinkIfOld(dirent.path, cutoffDate)) {
        result = CleanupResult(
          messages: result.messages + 1,
          errors: result.errors,
        );
      }
    } catch (_) {
      result = CleanupResult(
        messages: result.messages,
        errors: result.errors + 1,
      );
    }
  }

  if (removeEmptyDir) {
    await _tryRmdir(dirPath);
  }

  return result;
}

/// Clean up old plan files from ~/.neomage/plans/.
Future<CleanupResult> cleanupOldPlanFiles() {
  final plansDir = p.join(_getNeomageConfigHomeDir(), 'plans');
  return _cleanupSingleDirectory(plansDir, '.md');
}

/// Clean up old file history backups.
Future<CleanupResult> cleanupOldFileHistoryBackups() async {
  final cutoffDate = getCutoffDate();
  var result = const CleanupResult();

  try {
    final configDir = _getNeomageConfigHomeDir();
    final fileHistoryDir = p.join(configDir, 'file-history');

    List<FileSystemEntity> dirents;
    try {
      dirents = await Directory(fileHistoryDir).list().toList();
    } catch (_) {
      return result;
    }

    final sessionDirs = dirents.whereType<Directory>().toList();

    await Future.wait(
      sessionDirs.map((sessionDir) async {
        try {
          final stat = await FileStat.stat(sessionDir.path);
          if (stat.modified.isBefore(cutoffDate)) {
            await sessionDir.delete(recursive: true);
            result = CleanupResult(
              messages: result.messages + 1,
              errors: result.errors,
            );
          }
        } catch (_) {
          result = CleanupResult(
            messages: result.messages,
            errors: result.errors + 1,
          );
        }
      }),
    );

    await _tryRmdir(fileHistoryDir);
  } catch (_) {}

  return result;
}

/// Clean up old session environment directories.
Future<CleanupResult> cleanupOldSessionEnvDirs() async {
  final cutoffDate = getCutoffDate();
  var result = const CleanupResult();

  try {
    final configDir = _getNeomageConfigHomeDir();
    final sessionEnvBaseDir = p.join(configDir, 'session-env');

    List<FileSystemEntity> dirents;
    try {
      dirents = await Directory(sessionEnvBaseDir).list().toList();
    } catch (_) {
      return result;
    }

    final sessionEnvDirs = dirents.whereType<Directory>().toList();

    for (final sessionEnvDir in sessionEnvDirs) {
      try {
        final stat = await FileStat.stat(sessionEnvDir.path);
        if (stat.modified.isBefore(cutoffDate)) {
          await sessionEnvDir.delete(recursive: true);
          result = CleanupResult(
            messages: result.messages + 1,
            errors: result.errors,
          );
        }
      } catch (_) {
        result = CleanupResult(
          messages: result.messages,
          errors: result.errors + 1,
        );
      }
    }

    await _tryRmdir(sessionEnvBaseDir);
  } catch (_) {}

  return result;
}

/// Clean up old debug log files from ~/.neomage/debug/.
/// Preserves the 'latest' symlink.
Future<CleanupResult> cleanupOldDebugLogs() async {
  final cutoffDate = getCutoffDate();
  var result = const CleanupResult();
  final debugDir = p.join(_getNeomageConfigHomeDir(), 'debug');

  List<FileSystemEntity> dirents;
  try {
    dirents = await Directory(debugDir).list().toList();
  } catch (_) {
    return result;
  }

  for (final dirent in dirents) {
    if (dirent is! File) continue;
    final name = p.basename(dirent.path);
    if (!name.endsWith('.txt') || name == 'latest') continue;
    try {
      if (await _unlinkIfOld(dirent.path, cutoffDate)) {
        result = CleanupResult(
          messages: result.messages + 1,
          errors: result.errors,
        );
      }
    } catch (_) {
      result = CleanupResult(
        messages: result.messages,
        errors: result.errors + 1,
      );
    }
  }

  // Intentionally do NOT remove debugDir — needed for future logs.
  return result;
}

/// Run all cleanup operations in the background.
Future<void> cleanupOldMessageFilesInBackground() async {
  // Guard: skip if settings have validation errors but cleanupPeriodDays
  // was explicitly set.
  if (_rawSettingsContainsKey('cleanupPeriodDays')) {
    // Check for settings validation errors would go here.
    // Simplified: we always proceed in the Dart port.
  }

  await cleanupOldMessageFiles();
  await cleanupOldSessionFiles();
  await cleanupOldPlanFiles();
  await cleanupOldFileHistoryBackups();
  await cleanupOldSessionEnvDirs();
  await cleanupOldDebugLogs();
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 2 — Graceful Shutdown (from gracefulShutdown.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Exit reason enumeration.
enum ExitReason { userRequest, signal, error, other }

/// Callback type for cleanup functions registered at shutdown.
typedef CleanupCallback = Future<void> Function();

/// Callback type for session-end hooks.
typedef SessionEndHooksFn =
    Future<void> Function(ExitReason reason, {int? timeoutMs});

/// Callback type for analytics shutdown.
typedef AnalyticsShutdownFn = Future<void> Function();

/// Global list of cleanup functions.
final List<CleanupCallback> _cleanupFunctions = [];

/// Register a cleanup function to run during graceful shutdown.
void registerCleanup(CleanupCallback fn) {
  _cleanupFunctions.add(fn);
}

/// Run all registered cleanup functions.
Future<void> runCleanupFunctions() async {
  for (final fn in _cleanupFunctions) {
    try {
      await fn();
    } catch (_) {
      // Silently ignore cleanup errors.
    }
  }
}

/// Whether shutdown is currently in progress.
bool _shutdownInProgress = false;

/// Whether the resume hint has been printed.
bool _resumeHintPrinted = false;

/// Failsafe timer handle.
Timer? _failsafeTimer;

/// Check if graceful shutdown is in progress.
bool isShuttingDown() => _shutdownInProgress;

/// Reset shutdown state — only for use in tests.
void resetShutdownState() {
  _shutdownInProgress = false;
  _resumeHintPrinted = false;
  _failsafeTimer?.cancel();
  _failsafeTimer = null;
}

/// Global session-end hooks callback.
SessionEndHooksFn? _sessionEndHooks;

/// Global analytics shutdown callback.
AnalyticsShutdownFn? _analyticsShutdown;

/// Set the session-end hooks executor.
void setSessionEndHooks(SessionEndHooksFn fn) {
  _sessionEndHooks = fn;
}

/// Set the analytics shutdown executor.
void setAnalyticsShutdown(AnalyticsShutdownFn fn) {
  _analyticsShutdown = fn;
}

/// Global resume hint callback.
void Function()? _printResumeHintFn;

/// Set a callback for printing the resume hint.
void setPrintResumeHint(void Function() fn) {
  _printResumeHintFn = fn;
}

/// Print the resume hint (delegated to the registered callback).
void _printResumeHint() {
  if (_resumeHintPrinted) return;
  _printResumeHintFn?.call();
  _resumeHintPrinted = true;
}

/// Global terminal cleanup callback.
void Function()? _cleanupTerminalModesFn;

/// Set the terminal cleanup callback.
void setCleanupTerminalModes(void Function() fn) {
  _cleanupTerminalModesFn = fn;
}

/// Clean up terminal modes.
void _cleanupTerminalModes() {
  _cleanupTerminalModesFn?.call();
}

/// Force process exit.
Never _forceExit(int exitCode) {
  _failsafeTimer?.cancel();
  _failsafeTimer = null;
  exit(exitCode);
  throw StateError('Process should have exited with code $exitCode');
}

/// Set up global signal handlers for graceful shutdown.
/// Memoized — safe to call multiple times.
bool _signalHandlersSetUp = false;

void setupGracefulShutdown() {
  if (_signalHandlersSetUp) return;
  _signalHandlersSetUp = true;

  // SIGINT handler.
  ProcessSignal.sigint.watch().listen((_) {
    _logDiag('info', 'shutdown_signal', {'signal': 'SIGINT'});
    gracefulShutdown(exitCode: 0);
  });

  // SIGTERM handler.
  ProcessSignal.sigterm.watch().listen((_) {
    _logDiag('info', 'shutdown_signal', {'signal': 'SIGTERM'});
    gracefulShutdown(exitCode: 143);
  });

  // SIGHUP handler (Unix only).
  if (!Platform.isWindows) {
    try {
      ProcessSignal.sighup.watch().listen((_) {
        _logDiag('info', 'shutdown_signal', {'signal': 'SIGHUP'});
        gracefulShutdown(exitCode: 129);
      });
    } catch (_) {
      // Signal not available on this platform.
    }
  }
}

/// Synchronous wrapper that kicks off graceful shutdown.
void gracefulShutdownSync({
  int exitCode = 0,
  ExitReason reason = ExitReason.other,
}) {
  exitCode = exitCode; // ignore: parameter_assignments
  gracefulShutdown(exitCode: exitCode, reason: reason);
}

/// Graceful shutdown: cleans up resources, runs hooks, flushes analytics, exits.
Future<void> gracefulShutdown({
  int exitCode = 0,
  ExitReason reason = ExitReason.other,
  String? finalMessage,
}) async {
  if (_shutdownInProgress) return;
  _shutdownInProgress = true;

  // Resolve the session-end hook budget.
  const sessionEndTimeoutMs = 1500;

  // Failsafe: guarantee process exits even if cleanup hangs.
  final failsafeBudget =
      const Duration(milliseconds: 5000).inMilliseconds >
          sessionEndTimeoutMs + 3500
      ? const Duration(milliseconds: 5000)
      : Duration(milliseconds: sessionEndTimeoutMs + 3500);
  _failsafeTimer = Timer(failsafeBudget, () {
    _cleanupTerminalModes();
    _printResumeHint();
    _forceExit(exitCode);
  });

  // Exit alt screen and print resume hint first.
  _cleanupTerminalModes();
  _printResumeHint();

  // Flush session data — most critical cleanup.
  try {
    await runCleanupFunctions().timeout(const Duration(seconds: 2));
  } catch (_) {
    // Silently handle timeout and other errors.
  }

  // Execute SessionEnd hooks.
  try {
    if (_sessionEndHooks != null) {
      await _sessionEndHooks!(reason, timeoutMs: sessionEndTimeoutMs);
    }
  } catch (_) {
    // Ignore exceptions (including AbortError on timeout).
  }

  // Flush analytics — capped at 500 ms.
  try {
    if (_analyticsShutdown != null) {
      await _analyticsShutdown!().timeout(const Duration(milliseconds: 500));
    }
  } catch (_) {
    // Ignore analytics shutdown errors.
  }

  if (finalMessage != null) {
    try {
      stderr.writeln(finalMessage);
    } catch (_) {
      // stderr may be closed.
    }
  }

  _forceExit(exitCode);
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 3 — Background Housekeeping (from backgroundHousekeeping.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Recurring cleanup interval (24 hours).
const Duration _recurringCleanupInterval = Duration(hours: 24);

/// Delay for very slow operations (10 minutes after start).
const Duration _delayVerySlowOps = Duration(minutes: 10);

/// Global getters for interactive state (set by the app at startup).
bool Function() _getIsInteractive = () => false;
int Function() _getLastInteractionTime = () => 0;

/// Set the interactive-state getters.
void setHousekeepingInteractiveState({
  required bool Function() isInteractive,
  required int Function() lastInteractionTime,
}) {
  _getIsInteractive = isInteractive;
  _getLastInteractionTime = lastInteractionTime;
}

/// Start background housekeeping tasks.
void startBackgroundHousekeeping() {
  bool needsCleanup = true;

  Future<void> runVerySlowOps() async {
    // If the user did something in the last minute, defer.
    if (_getIsInteractive() &&
        _getLastInteractionTime() >
            DateTime.now().millisecondsSinceEpoch - 60000) {
      Timer(_delayVerySlowOps, () {
        runVerySlowOps();
      });
      return;
    }

    if (needsCleanup) {
      needsCleanup = false;
      await cleanupOldMessageFilesInBackground();
    }

    // If the user did something in the last minute, defer.
    if (_getIsInteractive() &&
        _getLastInteractionTime() >
            DateTime.now().millisecondsSinceEpoch - 60000) {
      Timer(_delayVerySlowOps, () {
        runVerySlowOps();
      });
      return;
    }

    // cleanupOldVersions() equivalent would go here.
  }

  Timer(_delayVerySlowOps, () {
    runVerySlowOps();
  });

  // For long-running sessions, schedule recurring cleanup every 24 hours.
  final userType = Platform.environment['USER_TYPE'];
  if (userType == 'ant') {
    Timer.periodic(_recurringCleanupInterval, (_) {
      // cleanupNpmCacheForAnthropicPackages() equivalent.
      // cleanupOldVersionsThrottled() equivalent.
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 4 — Cleanup Registry (mirrors cleanupRegistry.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Registered cleanup functions are already handled above via
/// [registerCleanup] and [runCleanupFunctions].

// ═══════════════════════════════════════════════════════════════════════════
// Part 5 — npm cache cleanup (from cleanup.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Throttled wrapper around version cleanup.
/// Uses a marker file and lock to ensure it runs at most once per 24 hours.
Future<void> cleanupOldVersionsThrottled() async {
  final markerPath = p.join(_getNeomageConfigHomeDir(), '.version-cleanup');

  try {
    final stat = await FileStat.stat(markerPath);
    if (DateTime.now().difference(stat.modified).inMilliseconds < _oneDayMs) {
      return; // Ran recently — skip.
    }
  } catch (_) {
    // File doesn't exist, proceed with cleanup.
  }

  try {
    // cleanupOldVersions() would go here.
    await File(markerPath).writeAsString(DateTime.now().toIso8601String());
  } catch (_) {}
}

/// Clean up old npm cache entries for Anthropic packages.
/// Only runs once per day for Ant users.
Future<void> cleanupNpmCacheForAnthropicPackages() async {
  final markerPath = p.join(_getNeomageConfigHomeDir(), '.npm-cache-cleanup');

  try {
    final stat = await FileStat.stat(markerPath);
    if (DateTime.now().difference(stat.modified).inMilliseconds < _oneDayMs) {
      return; // Ran recently — skip.
    }
  } catch (_) {
    // File doesn't exist, proceed with cleanup.
  }

  final startTime = DateTime.now().millisecondsSinceEpoch;
  try {
    // In the Dart port, npm cache cleanup is a no-op (no npm cache in Dart).
    // Marker file is still written to maintain the throttle contract.
    await File(markerPath).writeAsString(DateTime.now().toIso8601String());

    final durationMs = DateTime.now().millisecondsSinceEpoch - startTime;
    _logDiag('info', 'npm_cache_cleanup', {
      'success': true,
      'durationMs': durationMs,
    });
  } catch (_) {
    _logDiag('info', 'npm_cache_cleanup', {
      'success': false,
      'durationMs': DateTime.now().millisecondsSinceEpoch - startTime,
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Lightweight diagnostic logger (no PII).
void _logDiag(String level, String event, [Map<String, dynamic>? data]) {
  final logFile = Platform.environment['MAGE_DIAGNOSTICS_FILE'];
  if (logFile == null) return;

  final entry = <String, dynamic>{
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'level': level,
    'event': event,
    'data': data ?? {},
  };

  try {
    File(
      logFile,
    ).writeAsStringSync('${_jsonEncode(entry)}\n', mode: FileMode.append);
  } catch (_) {}
}

/// JSON encode with fallback.
String _jsonEncode(Object? value) {
  try {
    return const JsonEncoder().convert(value);
  } catch (_) {
    return '{}';
  }
}

/// JSON encoder import.
class JsonEncoder {
  const JsonEncoder();
  String convert(Object? value) => _dartJsonEncode(value);
}

String _dartJsonEncode(Object? value) {
  // Use dart:convert directly.
  return _realJsonEncode(value);
}

// Dart-native JSON encoding (we shadow the class above to avoid import).
// This is a workaround to keep the file self-contained.
String _realJsonEncode(Object? value) {
  final sink = StringBuffer();
  final encoder = const _RealJsonEncoder();
  encoder.writeTo(value, sink);
  return sink.toString();
}

class _RealJsonEncoder {
  const _RealJsonEncoder();
  void writeTo(Object? value, StringBuffer sink) {
    sink.write(_encode(value));
  }

  static String _encode(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    if (value is String) return '"${_escapeString(value)}"';
    if (value is List) {
      return '[${value.map(_encode).join(',')}]';
    }
    if (value is Map) {
      final entries = value.entries.map(
        (e) => '"${_escapeString(e.key.toString())}":${_encode(e.value)}',
      );
      return '{${entries.join(',')}}';
    }
    return '"${_escapeString(value.toString())}"';
  }

  static String _escapeString(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
