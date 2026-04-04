// Doctor diagnostic — port of openneomclaw doctorDiagnostic.ts +
// doctorContextWarnings.ts + diagLogs.ts + debug.ts + debugFilter.ts.
// Installation diagnostics, context warnings, debug logging with
// buffered writer, and debug message filtering.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════
// Part 1 — Diagnostic logs (from diagLogs.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Diagnostic log level for container-side monitoring.
enum DiagnosticLogLevel {
  debug,
  info,
  warn,
  error;

  @override
  String toString() => name;
}

/// A single diagnostic log entry written as JSON.
class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.timestamp,
    required this.level,
    required this.event,
    required this.data,
  });

  final String timestamp;
  final DiagnosticLogLevel level;
  final String event;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'level': level.name,
        'event': event,
        'data': data,
      };
}

/// Returns the diagnostic log file path from the environment, or `null` if
/// diagnostics logging is not configured.
String? _getDiagnosticLogFile() {
  return Platform.environment['NEOMCLAW_DIAGNOSTICS_FILE'];
}

/// Logs diagnostic information to a logfile. This information is sent via
/// the environment manager to session-ingress for container monitoring.
///
/// **Important** — this function MUST NOT be called with any PII, including
/// file paths, project names, repo names, prompts, etc.
///
/// [level]  Log level. Only used for information, not filtering.
/// [event]  A specific event: "started", "mcp_connected", etc.
/// [data]   Optional additional data to log.
void logForDiagnosticsNoPII(
  DiagnosticLogLevel level,
  String event, {
  Map<String, dynamic>? data,
}) {
  final logFile = _getDiagnosticLogFile();
  if (logFile == null) return;

  final entry = DiagnosticLogEntry(
    timestamp: DateTime.now().toUtc().toIso8601String(),
    level: level,
    event: event,
    data: data ?? {},
  );

  final line = '${jsonEncode(entry.toJson())}\n';

  try {
    File(logFile).writeAsStringSync(line, mode: FileMode.append);
  } catch (_) {
    // If append fails, try creating the directory first.
    try {
      Directory(p.dirname(logFile)).createSync(recursive: true);
      File(logFile).writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {
      // Silently fail if logging is not possible.
    }
  }
}

/// Wraps an async function with diagnostic timing logs.
///
/// Logs `{event}_started` before execution and `{event}_completed` after
/// with `duration_ms`.
///
/// [event]    Event name prefix (e.g., "git_status" -> logs
///            "git_status_started" and "git_status_completed").
/// [fn]       Async function to execute and time.
/// [getData]  Optional function to extract additional data from the result
///            for the completion log.
Future<T> withDiagnosticsTiming<T>(
  String event,
  Future<T> Function() fn, {
  Map<String, dynamic> Function(T result)? getData,
}) async {
  final startTime = DateTime.now().millisecondsSinceEpoch;
  logForDiagnosticsNoPII(DiagnosticLogLevel.info, '${event}_started');

  try {
    final result = await fn();
    final additionalData = getData != null ? getData(result) : <String, dynamic>{};
    logForDiagnosticsNoPII(
      DiagnosticLogLevel.info,
      '${event}_completed',
      data: {
        'duration_ms': DateTime.now().millisecondsSinceEpoch - startTime,
        ...additionalData,
      },
    );
    return result;
  } catch (error) {
    logForDiagnosticsNoPII(
      DiagnosticLogLevel.error,
      '${event}_failed',
      data: {
        'duration_ms': DateTime.now().millisecondsSinceEpoch - startTime,
      },
    );
    rethrow;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 2 — Debug logging (from debug.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Debug log level hierarchy from most to least verbose.
enum DebugLogLevel {
  verbose(0),
  debug(1),
  info(2),
  warn(3),
  error(4);

  const DebugLogLevel(this.order);

  /// Numeric order for level comparison.
  final int order;

  @override
  String toString() => name;
}

/// Map from level name to enum value for parsing.
final Map<String, DebugLogLevel> _debugLogLevelByName = {
  for (final level in DebugLogLevel.values) level.name: level,
};

/// Whether runtime debug logging has been enabled mid-session (e.g., via
/// /debug command).
bool _runtimeDebugEnabled = false;

/// Cached minimum debug log level. Defaults to [DebugLogLevel.debug], which
/// filters out verbose messages.
DebugLogLevel? _cachedMinDebugLogLevel;

/// Returns the minimum log level to include in debug output.
///
/// Set `NEOMCLAW_DEBUG_LOG_LEVEL=verbose` to include high-volume
/// diagnostics that would otherwise drown out useful debug output.
DebugLogLevel getMinDebugLogLevel() {
  if (_cachedMinDebugLogLevel != null) return _cachedMinDebugLogLevel!;
  final raw =
      Platform.environment['NEOMCLAW_DEBUG_LOG_LEVEL']?.toLowerCase().trim();
  if (raw != null && _debugLogLevelByName.containsKey(raw)) {
    _cachedMinDebugLogLevel = _debugLogLevelByName[raw]!;
  } else {
    _cachedMinDebugLogLevel = DebugLogLevel.debug;
  }
  return _cachedMinDebugLogLevel!;
}

/// Cached result of [isDebugMode].
bool? _cachedIsDebugMode;

/// Returns `true` if debug logging is currently active.
///
/// Checks runtime flag, environment variables (`DEBUG`, `DEBUG_SDK`),
/// command-line arguments (`--debug`, `-d`, `--debug-to-stderr`, `-d2e`,
/// `--debug=pattern`, `--debug-file`).
bool isDebugMode() {
  if (_cachedIsDebugMode != null) return _cachedIsDebugMode!;

  final args = _getProcessArgs();
  final env = Platform.environment;

  _cachedIsDebugMode = _runtimeDebugEnabled ||
      _isEnvTruthy(env['DEBUG']) ||
      _isEnvTruthy(env['DEBUG_SDK']) ||
      args.contains('--debug') ||
      args.contains('-d') ||
      isDebugToStdErr() ||
      args.any((arg) => arg.startsWith('--debug=')) ||
      getDebugFilePath() != null;
  return _cachedIsDebugMode!;
}

/// Enables debug logging mid-session (e.g., via /debug). Non-ants don't
/// write debug logs by default, so this lets them start capturing without
/// restarting with --debug. Returns `true` if logging was already active.
bool enableDebugLogging() {
  final wasActive =
      isDebugMode() || Platform.environment['USER_TYPE'] == 'ant';
  _runtimeDebugEnabled = true;
  _cachedIsDebugMode = null; // Clear cache.
  return wasActive;
}

/// Cached debug filter parsed from `--debug=pattern`.
DebugFilter? _cachedDebugFilter;
bool _debugFilterParsed = false;

/// Extracts and parses the debug filter from command-line arguments.
DebugFilter? getDebugFilter() {
  if (_debugFilterParsed) return _cachedDebugFilter;
  _debugFilterParsed = true;

  final args = _getProcessArgs();
  final debugArg = args.cast<String?>().firstWhere(
        (arg) => arg != null && arg.startsWith('--debug='),
        orElse: () => null,
      );
  if (debugArg == null) {
    _cachedDebugFilter = null;
    return null;
  }

  final filterPattern = debugArg.substring('--debug='.length);
  _cachedDebugFilter = parseDebugFilter(filterPattern);
  return _cachedDebugFilter;
}

/// Cached value for [isDebugToStdErr].
bool? _cachedIsDebugToStdErr;

/// Returns `true` if debug output should go to stderr (`--debug-to-stderr`
/// or `-d2e`).
bool isDebugToStdErr() {
  if (_cachedIsDebugToStdErr != null) return _cachedIsDebugToStdErr!;
  final args = _getProcessArgs();
  _cachedIsDebugToStdErr =
      args.contains('--debug-to-stderr') || args.contains('-d2e');
  return _cachedIsDebugToStdErr!;
}

/// Cached debug file path.
String? _cachedDebugFilePath;
bool _debugFilePathParsed = false;

/// Returns the explicit debug file path from `--debug-file=path` or
/// `--debug-file path`, or `null` if not set.
String? getDebugFilePath() {
  if (_debugFilePathParsed) return _cachedDebugFilePath;
  _debugFilePathParsed = true;

  final args = _getProcessArgs();
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--debug-file=')) {
      _cachedDebugFilePath = arg.substring('--debug-file='.length);
      return _cachedDebugFilePath;
    }
    if (arg == '--debug-file' && i + 1 < args.length) {
      _cachedDebugFilePath = args[i + 1];
      return _cachedDebugFilePath;
    }
  }
  _cachedDebugFilePath = null;
  return null;
}

/// Whether the log message should be emitted at all.
bool _shouldLogDebugMessage(String message) {
  final env = Platform.environment;

  // Non-ants only write debug logs when debug mode is active.
  if (env['USER_TYPE'] != 'ant' && !isDebugMode()) {
    return false;
  }

  final filter = getDebugFilter();
  return shouldShowDebugMessage(message, filter);
}

/// Whether the terminal output has formatted (multi-line safe) output.
bool _hasFormattedOutput = false;

/// Sets whether the terminal output is using formatted mode.
void setHasFormattedOutput(bool value) => _hasFormattedOutput = value;

/// Returns whether the terminal output is using formatted mode.
bool getHasFormattedOutput() => _hasFormattedOutput;

// ---------------------------------------------------------------------------
// Buffered debug writer
// ---------------------------------------------------------------------------

/// Simple buffered writer that collects lines and flushes them either
/// periodically or when the buffer is full.
class _BufferedDebugWriter {
  _BufferedDebugWriter({
    required this.writeFn,
    this.flushIntervalMs = 1000,
    this.maxBufferSize = 100,
    this.immediateMode = false,
  }) {
    if (!immediateMode) {
      _flushTimer = Timer.periodic(
        Duration(milliseconds: flushIntervalMs),
        (_) => flush(),
      );
    }
  }

  final void Function(String content) writeFn;
  final int flushIntervalMs;
  final int maxBufferSize;
  final bool immediateMode;

  final List<String> _buffer = [];
  Timer? _flushTimer;

  /// Adds a line to the buffer (or writes immediately in immediate mode).
  void write(String content) {
    if (immediateMode) {
      writeFn(content);
      return;
    }
    _buffer.add(content);
    if (_buffer.length >= maxBufferSize) {
      flush();
    }
  }

  /// Flushes all buffered content to the underlying writer.
  void flush() {
    if (_buffer.isEmpty) return;
    final content = _buffer.join();
    _buffer.clear();
    try {
      writeFn(content);
    } catch (_) {
      // Silently swallow write errors.
    }
  }

  /// Disposes of the flush timer and flushes remaining content.
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    flush();
  }
}

_BufferedDebugWriter? _debugWriter;

/// Tracks whether the directory for the debug log has been ensured.
String? _ensuredDebugDir;

/// Returns (or creates) the global buffered debug writer.
_BufferedDebugWriter _getDebugWriter() {
  if (_debugWriter != null) return _debugWriter!;

  _debugWriter = _BufferedDebugWriter(
    immediateMode: isDebugMode(),
    writeFn: (content) {
      final path = getDebugLogPath();
      final dir = p.dirname(path);
      final needMkdir = _ensuredDebugDir != dir;
      _ensuredDebugDir = dir;

      if (isDebugMode()) {
        // Sync writes in immediate mode — async writes are lost on
        // process.exit() and keep the event loop alive.
        if (needMkdir) {
          try {
            Directory(dir).createSync(recursive: true);
          } catch (_) {
            // Already exists.
          }
        }
        File(path).writeAsStringSync(content, mode: FileMode.append);
        _updateLatestDebugLogSymlink();
        return;
      }

      // Buffered path: async write.
      () async {
        try {
          if (needMkdir) {
            await Directory(dir).create(recursive: true);
          }
          await File(path).writeAsString(content, mode: FileMode.append);
          _updateLatestDebugLogSymlink();
        } catch (_) {
          // Silently fail.
        }
      }();
    },
  );

  return _debugWriter!;
}

/// Flushes any pending debug log writes.
Future<void> flushDebugLogs() async {
  _debugWriter?.flush();
  // Allow a microtask round for any pending async writes.
  await Future<void>.delayed(Duration.zero);
}

/// Disposes the debug writer (call during shutdown).
void disposeDebugWriter() {
  _debugWriter?.dispose();
  _debugWriter = null;
}

/// The primary debug logging function.
///
/// Writes timestamped log lines to the debug log file. Respects the minimum
/// log level and debug filter. Multi-line messages are JSON-encoded when
/// formatted output is active to avoid breaking the JSONL format.
void logForDebugging(
  String message, {
  DebugLogLevel level = DebugLogLevel.debug,
}) {
  if (level.order < getMinDebugLogLevel().order) return;
  if (!_shouldLogDebugMessage(message)) return;

  var msg = message;
  // Multi-line messages break JSONL output, so encode them.
  if (_hasFormattedOutput && msg.contains('\n')) {
    msg = jsonEncode(msg);
  }

  final timestamp = DateTime.now().toUtc().toIso8601String();
  final output = '$timestamp [${level.name.toUpperCase()}] ${msg.trim()}\n';

  if (isDebugToStdErr()) {
    stderr.write(output);
    return;
  }

  _getDebugWriter().write(output);
}

/// Session ID accessor placeholder — in production this would come from
/// bootstrap state. Callers should provide via [setSessionId].
String _sessionId = '';

/// Sets the session ID used to derive the debug log file name.
void setSessionId(String id) => _sessionId = id;

/// Returns the current session ID.
String getSessionId() => _sessionId;

/// Returns the NeomClaw config home directory, defaulting to `~/.claude`.
String _getNeomClawConfigHomeDir() {
  return Platform.environment['NEOMCLAW_CONFIG_DIR'] ??
      p.join(Platform.environment['HOME'] ?? '.', '.neomclaw');
}

/// Returns the path for the debug log file.
///
/// Priority: `--debug-file` flag > `NEOMCLAW_DEBUG_LOGS_DIR` env >
/// `~/.neomclaw/debug/<sessionId>.txt`.
String getDebugLogPath() {
  return getDebugFilePath() ??
      Platform.environment['NEOMCLAW_DEBUG_LOGS_DIR'] ??
      p.join(_getNeomClawConfigHomeDir(), 'debug', '$_sessionId.txt');
}

/// Whether the symlink has already been updated this session.
bool _symlinkUpdated = false;

/// Updates the `latest` symlink in the debug log directory to point to the
/// current session's debug log.
void _updateLatestDebugLogSymlink() {
  if (_symlinkUpdated) return;
  _symlinkUpdated = true;

  try {
    final debugLogPath = getDebugLogPath();
    final debugLogsDir = p.dirname(debugLogPath);
    final latestSymlinkPath = p.join(debugLogsDir, 'latest');

    // Remove existing symlink.
    try {
      Link(latestSymlinkPath).deleteSync();
    } catch (_) {
      // Doesn't exist.
    }
    Link(latestSymlinkPath).createSync(debugLogPath);
  } catch (_) {
    // Silently fail if symlink creation fails.
  }
}

/// Logs errors for Ants only, always visible in production.
void logAntError(String context, Object error) {
  if (Platform.environment['USER_TYPE'] != 'ant') return;

  if (error is Error && error.stackTrace != null) {
    logForDebugging(
      '[ANT-ONLY] $context stack trace:\n${error.stackTrace}',
      level: DebugLogLevel.error,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Returns `true` if an environment variable value is truthy
/// (1, true, yes, on).
bool _isEnvTruthy(String? value) {
  if (value == null || value.isEmpty) return false;
  return const {'1', 'true', 'yes', 'on'}.contains(value.toLowerCase());
}

/// Returns the process command-line arguments. In production this is the
/// Dart VM's argument list; tests may override via zone value.
List<String> _getProcessArgs() {
  // In a Flutter context we may not have direct access to argv.
  // Use a zone-based override if provided.
  final override = Zone.current[#processArgs];
  if (override is List<String>) return override;

  // Fallback: Dart standalone exposes these via Platform.
  try {
    // ignore: deprecated_member_use
    return Platform.executableArguments;
  } catch (_) {
    return const [];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 3 — Debug filter (from debugFilter.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Parsed debug filter that controls which debug messages are shown.
class DebugFilter {
  const DebugFilter({
    required this.include,
    required this.exclude,
    required this.isExclusive,
  });

  /// Categories to include (used in inclusive mode).
  final List<String> include;

  /// Categories to exclude (used in exclusive mode).
  final List<String> exclude;

  /// When `true`, the filter is in exclusive mode (exclude matching).
  /// When `false`, the filter is in inclusive mode (include matching).
  final bool isExclusive;

  @override
  String toString() =>
      'DebugFilter(include: $include, exclude: $exclude, isExclusive: $isExclusive)';
}

/// Parse a debug filter string into a [DebugFilter] configuration.
///
/// Examples:
///  - `"api,hooks"` -> include only api and hooks categories
///  - `"!1p,!file"` -> exclude 1p and file categories
///  - `null`/empty  -> no filtering (show all)
DebugFilter? parseDebugFilter(String? filterString) {
  if (filterString == null || filterString.trim().isEmpty) return null;

  final filters =
      filterString.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toList();

  if (filters.isEmpty) return null;

  // Check for mixed inclusive/exclusive filters.
  final hasExclusive = filters.any((f) => f.startsWith('!'));
  final hasInclusive = filters.any((f) => !f.startsWith('!'));

  if (hasExclusive && hasInclusive) {
    // Mixed mode is unsupported — return null to show all messages.
    return null;
  }

  // Clean up filters: remove '!' prefix and normalise to lowercase.
  final cleanFilters = filters
      .map((f) => f.replaceFirst(RegExp(r'^!'), '').toLowerCase())
      .toList();

  return DebugFilter(
    include: hasExclusive ? const [] : cleanFilters,
    exclude: hasExclusive ? cleanFilters : const [],
    isExclusive: hasExclusive,
  );
}

/// Regular expressions for category extraction.
final RegExp _mcpPattern = RegExp(r'^MCP server ["\x27]([^"\x27]+)["\x27]');
final RegExp _prefixPattern = RegExp(r'^([^:\[]+):');
final RegExp _bracketPattern = RegExp(r'^\[([^\]]+)\]');
final RegExp _secondaryPattern =
    RegExp(r':\s*([^:]+?)(?:\s+(?:type|mode|status|event))?:');

/// Extract debug categories from a log message.
///
/// Supports multiple patterns:
///  - `"category: message"` -> `["category"]`
///  - `"[CATEGORY] message"` -> `["category"]`
///  - `'MCP server "name": message'` -> `["mcp", "name"]`
///  - `"[ANT-ONLY] 1P event: tengu_timer"` -> `["ant-only", "1p"]`
///
/// Returns lowercase categories for case-insensitive matching.
List<String> extractDebugCategories(String message) {
  final categories = <String>[];

  // Pattern 3: MCP server "servername" — check first to avoid false
  // positives.
  final mcpMatch = _mcpPattern.firstMatch(message);
  if (mcpMatch != null && mcpMatch.group(1) != null) {
    categories.add('mcp');
    categories.add(mcpMatch.group(1)!.toLowerCase());
  } else {
    // Pattern 1: "category: message" (simple prefix).
    final prefixMatch = _prefixPattern.firstMatch(message);
    if (prefixMatch != null && prefixMatch.group(1) != null) {
      categories.add(prefixMatch.group(1)!.trim().toLowerCase());
    }
  }

  // Pattern 2: [CATEGORY] at the start.
  final bracketMatch = _bracketPattern.firstMatch(message);
  if (bracketMatch != null && bracketMatch.group(1) != null) {
    categories.add(bracketMatch.group(1)!.trim().toLowerCase());
  }

  // Pattern 4: Check for "1P event:" in the message.
  if (message.toLowerCase().contains('1p event:')) {
    categories.add('1p');
  }

  // Pattern 5: Look for secondary categories after the first pattern.
  final secondaryMatch = _secondaryPattern.firstMatch(message);
  if (secondaryMatch != null && secondaryMatch.group(1) != null) {
    final secondary = secondaryMatch.group(1)!.trim().toLowerCase();
    // Only add if it's a reasonable category name.
    if (secondary.length < 30 && !secondary.contains(' ')) {
      categories.add(secondary);
    }
  }

  // Return de-duplicated categories.
  return categories.toSet().toList();
}

/// Check if debug message categories should be shown based on [filter].
bool shouldShowDebugCategories(
  List<String> categories,
  DebugFilter? filter,
) {
  // No filter means show everything.
  if (filter == null) return true;

  // If no categories found, exclude the message in both modes.
  if (categories.isEmpty) return false;

  if (filter.isExclusive) {
    // Exclusive mode: show if none of the categories are in the exclude list.
    return !categories.any((cat) => filter.exclude.contains(cat));
  } else {
    // Inclusive mode: show if any of the categories are in the include list.
    return categories.any((cat) => filter.include.contains(cat));
  }
}

/// Main function to check if a debug message should be shown.
///
/// Combines [extractDebugCategories] and [shouldShowDebugCategories].
bool shouldShowDebugMessage(String message, DebugFilter? filter) {
  // Fast path: no filter means show everything.
  if (filter == null) return true;

  final categories = extractDebugCategories(message);
  return shouldShowDebugCategories(categories, filter);
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 4 — Doctor diagnostic (from doctorDiagnostic.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Recognised installation types.
enum InstallationType {
  npmGlobal('npm-global'),
  npmLocal('npm-local'),
  native('native'),
  packageManager('package-manager'),
  development('development'),
  unknown('unknown');

  const InstallationType(this.label);

  /// The human-readable label matching the TypeScript union literal.
  final String label;

  @override
  String toString() => label;
}

/// Installation method as recorded in global config.
typedef InstallMethod = String;

/// Represents a detected installation on the system.
class DetectedInstallation {
  const DetectedInstallation({required this.type, required this.path});

  final String type;
  final String path;

  Map<String, String> toJson() => {'type': type, 'path': path};

  @override
  String toString() => 'DetectedInstallation(type: $type, path: $path)';
}

/// A diagnostic warning with a description and recommended fix.
class DiagnosticWarning {
  const DiagnosticWarning({required this.issue, required this.fix});

  final String issue;
  final String fix;

  Map<String, String> toJson() => {'issue': issue, 'fix': fix};

  @override
  String toString() => 'DiagnosticWarning(issue: $issue, fix: $fix)';
}

/// Ripgrep status information.
class RipgrepStatus {
  const RipgrepStatus({
    required this.working,
    required this.mode,
    this.systemPath,
  });

  final bool working;

  /// One of `system`, `builtin`, or `embedded`.
  final String mode;

  final String? systemPath;

  Map<String, dynamic> toJson() => {
        'working': working,
        'mode': mode,
        'systemPath': systemPath,
      };
}

/// Full diagnostic information gathered by the doctor command.
class DiagnosticInfo {
  const DiagnosticInfo({
    required this.installationType,
    required this.version,
    required this.installationPath,
    required this.invokedBinary,
    required this.configInstallMethod,
    required this.autoUpdates,
    required this.hasUpdatePermissions,
    required this.multipleInstallations,
    required this.warnings,
    this.recommendation,
    this.packageManager,
    required this.ripgrepStatus,
  });

  final InstallationType installationType;
  final String version;
  final String installationPath;
  final String invokedBinary;
  final String configInstallMethod;
  final String autoUpdates;
  final bool? hasUpdatePermissions;
  final List<DetectedInstallation> multipleInstallations;
  final List<DiagnosticWarning> warnings;
  final String? recommendation;
  final String? packageManager;
  final RipgrepStatus ripgrepStatus;

  Map<String, dynamic> toJson() => {
        'installationType': installationType.label,
        'version': version,
        'installationPath': installationPath,
        'invokedBinary': invokedBinary,
        'configInstallMethod': configInstallMethod,
        'autoUpdates': autoUpdates,
        'hasUpdatePermissions': hasUpdatePermissions,
        'multipleInstallations':
            multipleInstallations.map((i) => i.toJson()).toList(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        if (recommendation != null) 'recommendation': recommendation,
        if (packageManager != null) 'packageManager': packageManager,
        'ripgrepStatus': ripgrepStatus.toJson(),
      };

  @override
  String toString() => 'DiagnosticInfo(type: ${installationType.label}, '
      'version: $version, warnings: ${warnings.length})';
}

/// Normalises paths on Windows to use forward slashes for consistent
/// matching.
List<String> _getNormalizedPaths() {
  // In Dart/Flutter, we derive invoked path from Platform.resolvedExecutable
  // and executable.
  final invokedPath = Platform.resolvedExecutable;
  final execPath = Platform.executable;

  if (Platform.isWindows) {
    return [
      invokedPath.replaceAll('\\', '/'),
      execPath.replaceAll('\\', '/'),
    ];
  }
  return [invokedPath, execPath];
}

/// Determines the current installation type by examining paths and
/// environment.
///
/// Placeholder callback hooks allow the caller to inject platform-specific
/// detection (e.g., bundled mode, package manager detection). In production
/// these would be wired to actual detection functions.
Future<InstallationType> getCurrentInstallationType({
  bool Function()? isInBundledMode,
  bool Function()? isRunningFromLocal,
  Future<bool> Function()? detectPackageManager,
}) async {
  final env = Platform.environment;
  if (env['NODE_ENV'] == 'development' ||
      env['FLUTTER_ENV'] == 'development') {
    return InstallationType.development;
  }

  final paths = _getNormalizedPaths();
  final invokedPath = paths[0];

  // Check if running in bundled mode.
  if (isInBundledMode != null && isInBundledMode()) {
    if (detectPackageManager != null && await detectPackageManager()) {
      return InstallationType.packageManager;
    }
    return InstallationType.native;
  }

  // Check if running from local installation.
  if (isRunningFromLocal != null && isRunningFromLocal()) {
    return InstallationType.npmLocal;
  }

  // Check if we're in a typical npm global location.
  const npmGlobalPaths = [
    '/usr/local/lib/node_modules',
    '/usr/lib/node_modules',
    '/opt/homebrew/lib/node_modules',
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/.nvm/versions/node/',
  ];

  if (npmGlobalPaths.any((path) => invokedPath.contains(path))) {
    return InstallationType.npmGlobal;
  }

  if (invokedPath.contains('/npm/') || invokedPath.contains('/nvm/')) {
    return InstallationType.npmGlobal;
  }

  // Try to get the npm global prefix.
  try {
    final result = await Process.run('npm', ['config', 'get', 'prefix']);
    if (result.exitCode == 0) {
      final globalPrefix = (result.stdout as String).trim();
      if (globalPrefix.isNotEmpty && invokedPath.startsWith(globalPrefix)) {
        return InstallationType.npmGlobal;
      }
    }
  } catch (_) {
    // npm not available.
  }

  return InstallationType.unknown;
}

/// Returns the installation path by probing the filesystem and process
/// metadata.
Future<String> getInstallationPath({
  bool Function()? isInBundledMode,
}) async {
  final env = Platform.environment;
  if (env['NODE_ENV'] == 'development' ||
      env['FLUTTER_ENV'] == 'development') {
    return Directory.current.path;
  }

  if (isInBundledMode != null && isInBundledMode()) {
    try {
      return await File(Platform.resolvedExecutable).resolveSymbolicLinks();
    } catch (_) {
      // Fallback.
    }

    // Check which neomclaw.
    try {
      final result = await Process.run('which', ['neomclaw']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {
      // Not available.
    }

    // Check common locations.
    final home = env['HOME'] ?? '.';
    final localBin = p.join(home, '.local', 'bin', 'neomclaw');
    if (await File(localBin).exists()) return localBin;

    return 'native';
  }

  return Platform.resolvedExecutable;
}

/// Returns the binary path that was used to invoke the program.
String getInvokedBinary({
  bool Function()? isInBundledMode,
}) {
  try {
    if (isInBundledMode != null && isInBundledMode()) {
      return Platform.resolvedExecutable;
    }
    return Platform.executable;
  } catch (_) {
    return 'unknown';
  }
}

/// Detects multiple NeomClaw installations on the system.
Future<List<DetectedInstallation>> detectMultipleInstallations({
  Future<bool> Function()? localInstallationExists,
}) async {
  final installations = <DetectedInstallation>[];
  final home = Platform.environment['HOME'] ?? '.';

  // Check for local installation.
  final localPath = p.join(home, '.neomclaw', 'local');
  if (localInstallationExists != null && await localInstallationExists()) {
    installations
        .add(DetectedInstallation(type: 'npm-local', path: localPath));
  }

  // Check for global npm installation.
  try {
    final npmResult =
        await Process.run('npm', ['-g', 'config', 'get', 'prefix']);
    if (npmResult.exitCode == 0) {
      final npmPrefix = (npmResult.stdout as String).trim();
      if (npmPrefix.isNotEmpty) {
        final isWindows = Platform.isWindows;
        final globalBinPath = isWindows
            ? p.join(npmPrefix, 'neomclaw')
            : p.join(npmPrefix, 'bin', 'neomclaw');

        if (await File(globalBinPath).exists()) {
          installations.add(
            DetectedInstallation(type: 'npm-global', path: globalBinPath),
          );
        } else {
          // Check for orphaned packages.
          const packagesToCheck = ['@anthropic-ai/neom-claw'];
          for (final packageName in packagesToCheck) {
            final globalPackagePath = isWindows
                ? p.join(npmPrefix, 'node_modules', packageName)
                : p.join(npmPrefix, 'lib', 'node_modules', packageName);
            if (await Directory(globalPackagePath).exists()) {
              installations.add(DetectedInstallation(
                type: 'npm-global-orphan',
                path: globalPackagePath,
              ));
            }
          }
        }
      }
    }
  } catch (_) {
    // npm not available.
  }

  // Check for native installation.
  final nativeBinPath = p.join(home, '.local', 'bin', 'neomclaw');
  if (await File(nativeBinPath).exists()) {
    installations
        .add(DetectedInstallation(type: 'native', path: nativeBinPath));
  }

  // Also check if config indicates native installation.
  final nativeDataPath = p.join(home, '.local', 'share', 'neomclaw');
  if (await Directory(nativeDataPath).exists()) {
    if (!installations.any((i) => i.type == 'native')) {
      installations
          .add(DetectedInstallation(type: 'native', path: nativeDataPath));
    }
  }

  return installations;
}

/// Detects configuration issues for the given installation type.
///
/// [type]               The current installation type.
/// [configInstallMethod] The install method recorded in global config.
/// [localInstallationExists] Async check for local npm installation.
/// [getPlatformName]    Returns the platform name (linux, macos, windows).
Future<List<DiagnosticWarning>> detectConfigurationIssues(
  InstallationType type, {
  String? configInstallMethod,
  Future<bool> Function()? localInstallationExists,
  String Function()? getPlatformName,
}) async {
  final warnings = <DiagnosticWarning>[];
  final platform = getPlatformName?.call() ?? _currentPlatformName();

  // Skip most warnings for development mode.
  if (type == InstallationType.development) return warnings;

  // Check if ~/.local/bin is in PATH for native installations.
  if (type == InstallationType.native) {
    final pathEnv = Platform.environment['PATH'] ?? '';
    final pathDirectories = pathEnv.split(Platform.isWindows ? ';' : ':');
    final home = Platform.environment['HOME'] ?? '.';
    final localBinPath = p.join(home, '.local', 'bin');

    final localBinInPath = pathDirectories.any((dir) {
      var normalizedDir = dir;
      if (Platform.isWindows) {
        normalizedDir = dir.replaceAll('\\', '/');
      }
      final trimmedDir = normalizedDir.replaceAll(RegExp(r'/+$'), '');
      final trimmedRawDir = dir.replaceAll(RegExp(r'[/\\]+$'), '');
      return trimmedDir == localBinPath ||
          trimmedRawDir == '~/.local/bin' ||
          trimmedRawDir == r'$HOME/.local/bin';
    });

    if (!localBinInPath) {
      if (platform == 'windows') {
        final windowsLocalBinPath = localBinPath.replaceAll('/', '\\');
        warnings.add(DiagnosticWarning(
          issue:
              'Native installation exists but $windowsLocalBinPath is not in your PATH',
          fix:
              'Add it by opening: System Properties > Environment Variables > Edit User PATH > New > Add the path above. Then restart your terminal.',
        ));
      } else {
        warnings.add(DiagnosticWarning(
          issue:
              'Native installation exists but ~/.local/bin is not in your PATH',
          fix:
              'Run: echo \'export PATH="\$HOME/.local/bin:\$PATH"\' >> your shell config file then open a new terminal.',
        ));
      }
    }
  }

  // Check for configuration mismatches.
  final disableChecks =
      _isEnvTruthy(Platform.environment['DISABLE_INSTALLATION_CHECKS']);

  if (!disableChecks) {
    if (type == InstallationType.npmLocal &&
        configInstallMethod != null &&
        configInstallMethod != 'local') {
      warnings.add(DiagnosticWarning(
        issue:
            "Running from local installation but config install method is '$configInstallMethod'",
        fix: 'Consider using native installation: neomclaw install',
      ));
    }

    if (type == InstallationType.native &&
        configInstallMethod != null &&
        configInstallMethod != 'native') {
      warnings.add(DiagnosticWarning(
        issue:
            "Running native installation but config install method is '$configInstallMethod'",
        fix: 'Run neomclaw install to update configuration',
      ));
    }
  }

  if (type == InstallationType.npmGlobal &&
      localInstallationExists != null &&
      await localInstallationExists()) {
    warnings.add(DiagnosticWarning(
      issue: 'Local installation exists but not being used',
      fix: 'Consider using native installation: neomclaw install',
    ));
  }

  return warnings;
}

/// Detects glob pattern warnings for Linux sandboxing.
///
/// [globPatterns] A list of glob patterns found in sandbox permission rules.
List<DiagnosticWarning> detectLinuxGlobPatternWarnings({
  required List<String> globPatterns,
  String Function()? getPlatformName,
}) {
  final platform = getPlatformName?.call() ?? _currentPlatformName();
  if (platform != 'linux') return const [];
  if (globPatterns.isEmpty) return const [];

  // Show first 3 patterns, then indicate if there are more.
  final displayPatterns = globPatterns.take(3).join(', ');
  final remaining = globPatterns.length - 3;
  final patternList = remaining > 0
      ? '$displayPatterns ($remaining more)'
      : displayPatterns;

  return [
    DiagnosticWarning(
      issue:
          'Glob patterns in sandbox permission rules are not fully supported on Linux',
      fix:
          'Found ${globPatterns.length} pattern(s): $patternList. On Linux, glob patterns in Edit/Read rules will be ignored.',
    ),
  ];
}

/// Gathers full diagnostic information for the doctor command.
///
/// This is the main entry point. Callbacks allow injection of
/// platform-specific detection logic.
Future<DiagnosticInfo> getDoctorDiagnostic({
  bool Function()? isInBundledMode,
  bool Function()? isRunningFromLocal,
  Future<bool> Function()? detectPackageManagerFn,
  Future<bool> Function()? localInstallationExistsFn,
  String? version,
  String? configInstallMethod,
  String Function()? getAutoUpdatesStatus,
  Future<bool?> Function()? checkUpdatePermissions,
  RipgrepStatus Function()? getRipgrepStatusFn,
  Future<String?> Function()? getPackageManagerFn,
  List<String> Function()? getLinuxGlobPatternWarnings,
}) async {
  final installationType = await getCurrentInstallationType(
    isInBundledMode: isInBundledMode,
    isRunningFromLocal: isRunningFromLocal,
    detectPackageManager: detectPackageManagerFn,
  );

  final resolvedVersion = version ?? 'unknown';

  final installationPath = await getInstallationPath(
    isInBundledMode: isInBundledMode,
  );

  final invokedBinary = getInvokedBinary(
    isInBundledMode: isInBundledMode,
  );

  final multipleInstallations = await detectMultipleInstallations(
    localInstallationExists: localInstallationExistsFn,
  );

  final warnings = await detectConfigurationIssues(
    installationType,
    configInstallMethod: configInstallMethod,
    localInstallationExists: localInstallationExistsFn,
  );

  // Add glob pattern warnings for Linux sandboxing.
  if (getLinuxGlobPatternWarnings != null) {
    warnings.addAll(detectLinuxGlobPatternWarnings(
      globPatterns: getLinuxGlobPatternWarnings(),
    ));
  }

  // Add warnings for leftover npm installations when running native.
  if (installationType == InstallationType.native) {
    final npmInstalls = multipleInstallations.where(
      (i) =>
          i.type == 'npm-global' ||
          i.type == 'npm-global-orphan' ||
          i.type == 'npm-local',
    );

    for (final install in npmInstalls) {
      if (install.type == 'npm-global') {
        warnings.add(DiagnosticWarning(
          issue: 'Leftover npm global installation at ${install.path}',
          fix: 'Run: npm -g uninstall @anthropic-ai/neom-claw',
        ));
      } else if (install.type == 'npm-global-orphan') {
        warnings.add(DiagnosticWarning(
          issue: 'Orphaned npm global package at ${install.path}',
          fix: Platform.isWindows
              ? 'Run: rmdir /s /q "${install.path}"'
              : 'Run: rm -rf ${install.path}',
        ));
      } else if (install.type == 'npm-local') {
        warnings.add(DiagnosticWarning(
          issue: 'Leftover npm local installation at ${install.path}',
          fix: Platform.isWindows
              ? 'Run: rmdir /s /q "${install.path}"'
              : 'Run: rm -rf ${install.path}',
        ));
      }
    }
  }

  final resolvedConfigMethod = configInstallMethod ?? 'not set';

  // Check permissions for global installations.
  bool? hasUpdatePermissions;
  if (installationType == InstallationType.npmGlobal &&
      checkUpdatePermissions != null) {
    hasUpdatePermissions = await checkUpdatePermissions();
    if (hasUpdatePermissions == false) {
      warnings.add(DiagnosticWarning(
        issue: 'Insufficient permissions for auto-updates',
        fix:
            'Do one of: (1) Re-install node without sudo, or (2) Use `neomclaw install` for native installation',
      ));
    }
  }

  // Get ripgrep status.
  final ripgrepStatus = getRipgrepStatusFn?.call() ??
      const RipgrepStatus(
        working: true,
        mode: 'builtin',
      );

  // Get package manager info.
  final packageManager =
      installationType == InstallationType.packageManager &&
              getPackageManagerFn != null
          ? await getPackageManagerFn()
          : null;

  final autoUpdates = getAutoUpdatesStatus?.call() ?? 'unknown';

  return DiagnosticInfo(
    installationType: installationType,
    version: resolvedVersion,
    installationPath: installationPath,
    invokedBinary: invokedBinary,
    configInstallMethod: resolvedConfigMethod,
    autoUpdates: autoUpdates,
    hasUpdatePermissions: hasUpdatePermissions,
    multipleInstallations: multipleInstallations,
    warnings: warnings,
    packageManager: packageManager,
    ripgrepStatus: ripgrepStatus,
  );
}

/// Returns the current platform name as a lowercase string.
String _currentPlatformName() {
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  return 'unknown';
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 5 — Context warnings (from doctorContextWarnings.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Threshold for MCP tools token count.
const int mcpToolsThreshold = 25000;

/// Default threshold for agent descriptions token count.
const int agentDescriptionsThreshold = 5000;

/// Default max memory character count for a single NEOMCLAW.md file.
const int maxMemoryCharacterCount = 40000;

/// Severity level for context warnings.
enum ContextWarningSeverity {
  warning,
  error;

  @override
  String toString() => name;
}

/// Type of context warning.
enum ContextWarningType {
  neomclawmdFiles('neomclawmd_files'),
  agentDescriptions('agent_descriptions'),
  mcpTools('mcp_tools'),
  unreachableRules('unreachable_rules');

  const ContextWarningType(this.label);
  final String label;

  @override
  String toString() => label;
}

/// A single context warning from the doctor analysis.
class ContextWarning {
  const ContextWarning({
    required this.type,
    required this.severity,
    required this.message,
    required this.details,
    required this.currentValue,
    required this.threshold,
  });

  final ContextWarningType type;
  final ContextWarningSeverity severity;
  final String message;
  final List<String> details;
  final int currentValue;
  final int threshold;

  Map<String, dynamic> toJson() => {
        'type': type.label,
        'severity': severity.name,
        'message': message,
        'details': details,
        'currentValue': currentValue,
        'threshold': threshold,
      };

  @override
  String toString() => 'ContextWarning(${type.label}: $message)';
}

/// All context warnings grouped by type.
class ContextWarnings {
  const ContextWarnings({
    this.neomClawMdWarning,
    this.agentWarning,
    this.mcpWarning,
    this.unreachableRulesWarning,
  });

  final ContextWarning? neomClawMdWarning;
  final ContextWarning? agentWarning;
  final ContextWarning? mcpWarning;
  final ContextWarning? unreachableRulesWarning;

  /// Returns `true` if any warnings are present.
  bool get hasWarnings =>
      neomClawMdWarning != null ||
      agentWarning != null ||
      mcpWarning != null ||
      unreachableRulesWarning != null;

  /// Returns all non-null warnings as a flat list.
  List<ContextWarning> get all => [
        if (neomClawMdWarning != null) neomClawMdWarning!,
        if (agentWarning != null) agentWarning!,
        if (mcpWarning != null) mcpWarning!,
        if (unreachableRulesWarning != null) unreachableRulesWarning!,
      ];

  @override
  String toString() =>
      'ContextWarnings(${all.length} warning(s))';
}

/// Represents a memory file with its path and content.
class MemoryFileInfo {
  const MemoryFileInfo({required this.path, required this.content});

  final String path;
  final String content;
}

/// Check for large NEOMCLAW.md files.
///
/// [memoryFiles]            All loaded memory files.
/// [maxCharacterCount]      Per-file character threshold (default 40 000).
ContextWarning? checkNeomClawMdFiles(
  List<MemoryFileInfo> memoryFiles, {
  int maxCharacterCount = maxMemoryCharacterCount,
}) {
  // Filter for files exceeding the threshold.
  final largeFiles =
      memoryFiles.where((f) => f.content.length > maxCharacterCount).toList();

  if (largeFiles.isEmpty) return null;

  largeFiles.sort((a, b) => b.content.length.compareTo(a.content.length));

  final details =
      largeFiles.map((f) => '${f.path}: ${f.content.length} chars').toList();

  final message = largeFiles.length == 1
      ? 'Large NEOMCLAW.md file detected (${largeFiles[0].content.length} chars > $maxCharacterCount)'
      : '${largeFiles.length} large NEOMCLAW.md files detected (each > $maxCharacterCount chars)';

  return ContextWarning(
    type: ContextWarningType.neomclawmdFiles,
    severity: ContextWarningSeverity.warning,
    message: message,
    details: details,
    currentValue: largeFiles.length,
    threshold: maxCharacterCount,
  );
}

/// Agent definition with name and description for token counting.
class AgentDefinitionInfo {
  const AgentDefinitionInfo({
    required this.agentType,
    required this.whenToUse,
    this.source = 'custom',
  });

  final String agentType;
  final String whenToUse;
  final String source;
}

/// Rough token count estimation (approx 4 chars per token).
int _roughTokenCountEstimation(String text) {
  return (text.length / 4).ceil();
}

/// Check agent descriptions token count.
///
/// [agents]     All active agent definitions.
/// [threshold]  Token threshold (default [agentDescriptionsThreshold]).
ContextWarning? checkAgentDescriptions(
  List<AgentDefinitionInfo> agents, {
  int threshold = agentDescriptionsThreshold,
}) {
  // Filter out built-in agents and compute total tokens.
  final customAgents = agents.where((a) => a.source != 'built-in').toList();

  final totalTokens = customAgents.fold<int>(0, (sum, agent) {
    final description = '${agent.agentType}: ${agent.whenToUse}';
    return sum + _roughTokenCountEstimation(description);
  });

  if (totalTokens <= threshold) return null;

  // Calculate tokens for each agent.
  final agentTokens = customAgents.map((agent) {
    final description = '${agent.agentType}: ${agent.whenToUse}';
    return (
      name: agent.agentType,
      tokens: _roughTokenCountEstimation(description),
    );
  }).toList()
    ..sort((a, b) => b.tokens.compareTo(a.tokens));

  final details = agentTokens
      .take(5)
      .map((agent) => '${agent.name}: ~${agent.tokens} tokens')
      .toList();

  if (agentTokens.length > 5) {
    details.add('(${agentTokens.length - 5} more custom agents)');
  }

  return ContextWarning(
    type: ContextWarningType.agentDescriptions,
    severity: ContextWarningSeverity.warning,
    message: 'Large agent descriptions (~$totalTokens tokens > $threshold)',
    details: details,
    currentValue: totalTokens,
    threshold: threshold,
  );
}

/// Information about an MCP tool for token counting.
class McpToolInfo {
  const McpToolInfo({
    required this.name,
    required this.description,
    required this.isMcp,
  });

  final String name;
  final String description;
  final bool isMcp;
}

/// Detailed MCP tool token info (from analysis).
class McpToolTokenDetail {
  const McpToolTokenDetail({required this.name, required this.tokens});

  final String name;
  final int tokens;
}

/// Check MCP tools token count.
///
/// [tools]          All registered tools.
/// [mcpToolTokens]  Pre-computed total MCP tool token count. If null, a
///                  rough estimation is used.
/// [mcpToolDetails] Per-tool token details (optional).
/// [threshold]      Token threshold (default [mcpToolsThreshold]).
ContextWarning? checkMcpTools(
  List<McpToolInfo> tools, {
  int? mcpToolTokens,
  List<McpToolTokenDetail>? mcpToolDetails,
  int threshold = mcpToolsThreshold,
}) {
  final mcpTools = tools.where((t) => t.isMcp).toList();
  if (mcpTools.isEmpty) return null;

  // Use provided token count or estimate.
  final totalTokens = mcpToolTokens ??
      mcpTools.fold<int>(0, (sum, tool) {
        final chars = tool.name.length + tool.description.length;
        return sum + _roughTokenCountEstimation(chars.toString());
      });

  if (totalTokens <= threshold) return null;

  // Build per-server breakdown if details are available.
  final List<String> details;
  if (mcpToolDetails != null && mcpToolDetails.isNotEmpty) {
    // Group tools by server.
    final toolsByServer = <String, ({int count, int tokens})>{};
    for (final tool in mcpToolDetails) {
      final parts = tool.name.split('__');
      final serverName = parts.length > 1 ? parts[1] : 'unknown';
      final current = toolsByServer[serverName] ?? (count: 0, tokens: 0);
      toolsByServer[serverName] = (
        count: current.count + 1,
        tokens: current.tokens + tool.tokens,
      );
    }

    // Sort by token count.
    final sortedServers = toolsByServer.entries.toList()
      ..sort((a, b) => b.value.tokens.compareTo(a.value.tokens));

    details = sortedServers
        .take(5)
        .map((e) => '${e.key}: ${e.value.count} tools (~${e.value.tokens} tokens)')
        .toList();

    if (sortedServers.length > 5) {
      details.add('(${sortedServers.length - 5} more servers)');
    }
  } else {
    details = ['${mcpTools.length} MCP tools detected (token count estimated)'];
  }

  return ContextWarning(
    type: ContextWarningType.mcpTools,
    severity: ContextWarningSeverity.warning,
    message: 'Large MCP tools context (~$totalTokens tokens > $threshold)',
    details: details,
    currentValue: totalTokens,
    threshold: threshold,
  );
}

/// An unreachable permission rule detected by shadow analysis.
class UnreachableRule {
  const UnreachableRule({
    required this.ruleDescription,
    required this.reason,
    required this.fix,
  });

  final String ruleDescription;
  final String reason;
  final String fix;
}

/// Check for unreachable permission rules.
///
/// [unreachableRules] Pre-detected unreachable rules from shadow analysis.
ContextWarning? checkUnreachableRules(
  List<UnreachableRule> unreachableRules,
) {
  if (unreachableRules.isEmpty) return null;

  final details = unreachableRules
      .expand((r) => [
            '${r.ruleDescription}: ${r.reason}',
            '  Fix: ${r.fix}',
          ])
      .toList();

  final count = unreachableRules.length;
  final plural = count == 1
      ? 'unreachable permission rule'
      : 'unreachable permission rules';

  return ContextWarning(
    type: ContextWarningType.unreachableRules,
    severity: ContextWarningSeverity.warning,
    message: '$count $plural detected',
    details: details,
    currentValue: count,
    threshold: 0,
  );
}

/// Check all context warnings for the doctor command.
///
/// Runs all checks in parallel and returns the aggregated results.
Future<ContextWarnings> checkContextWarnings({
  required List<MemoryFileInfo> memoryFiles,
  required List<AgentDefinitionInfo> agents,
  required List<McpToolInfo> tools,
  required List<UnreachableRule> unreachableRules,
  int? mcpToolTokens,
  List<McpToolTokenDetail>? mcpToolDetails,
}) async {
  // All checks are synchronous in this port, but we preserve the async
  // signature for API compatibility.
  final neomClawMdWarning = checkNeomClawMdFiles(memoryFiles);
  final agentWarning = checkAgentDescriptions(agents);
  final mcpWarning = checkMcpTools(
    tools,
    mcpToolTokens: mcpToolTokens,
    mcpToolDetails: mcpToolDetails,
  );
  final unreachableRulesWarning = checkUnreachableRules(unreachableRules);

  return ContextWarnings(
    neomClawMdWarning: neomClawMdWarning,
    agentWarning: agentWarning,
    mcpWarning: mcpWarning,
    unreachableRulesWarning: unreachableRulesWarning,
  );
}
