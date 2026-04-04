// Error handling — port of neom_claw/src/utils/errors/.
// Structured errors, diagnostics, recovery, reporting.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

// ─── Error types ───

/// Base error for all Neom Claw errors.
abstract class ClawError implements Exception {
  String get message;
  String get errorId;
  String? get suggestion;
  Map<String, dynamic> get context;

  @override
  String toString() => '$runtimeType($errorId): $message';
}

/// API-related errors.
class ApiError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final int? statusCode;
  final String? errorType;
  final Map<String, dynamic>? responseBody;

  ApiError({
    required this.message,
    this.errorId = 'api_error',
    this.suggestion,
    this.statusCode,
    this.errorType,
    this.responseBody,
  });

  @override
  Map<String, dynamic> get context => {
        if (statusCode != null) 'statusCode': statusCode,
        if (errorType != null) 'errorType': errorType,
      };

  /// Create from HTTP status code.
  factory ApiError.fromStatus(int statusCode, {String? body}) {
    final parsed =
        body != null ? _tryParseJson(body) : null;
    final msg = parsed?['error']?['message'] as String? ??
        _defaultMessage(statusCode);
    return ApiError(
      message: msg,
      errorId: 'api_${statusCode}',
      statusCode: statusCode,
      errorType: parsed?['error']?['type'] as String?,
      responseBody: parsed,
      suggestion: _suggestion(statusCode),
    );
  }

  static String _defaultMessage(int code) => switch (code) {
        400 => 'Bad request — check your input.',
        401 => 'Authentication failed.',
        403 => 'Access forbidden.',
        404 => 'Resource not found.',
        429 => 'Rate limited.',
        500 => 'Internal server error.',
        502 => 'Bad gateway.',
        503 => 'Service unavailable.',
        529 => 'API overloaded.',
        _ => 'HTTP error $code.',
      };

  static String? _suggestion(int code) => switch (code) {
        401 => 'Check your API key with /login or set ANTHROPIC_API_KEY.',
        429 =>
          'You\'re being rate limited. Wait a moment and try again.',
        529 =>
          'The API is temporarily overloaded. Please try again shortly.',
        _ => null,
      };

  bool get isRetryable =>
      statusCode != null &&
      {429, 500, 502, 503, 529}.contains(statusCode);
}

/// Tool execution errors.
class ToolError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final String toolName;
  final Map<String, dynamic> input;

  ToolError({
    required this.message,
    required this.toolName,
    this.input = const {},
    this.errorId = 'tool_error',
    this.suggestion,
  });

  @override
  Map<String, dynamic> get context => {
        'toolName': toolName,
        'input': input,
      };
}

/// Permission errors.
class PermissionError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final String operation;

  PermissionError({
    required this.operation,
    this.message = 'Permission denied.',
    this.errorId = 'permission_denied',
    this.suggestion,
  });

  @override
  Map<String, dynamic> get context => {'operation': operation};
}

/// File system errors.
class FileSystemError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final String path;
  final String operation;

  FileSystemError({
    required this.message,
    required this.path,
    required this.operation,
    this.errorId = 'fs_error',
    this.suggestion,
  });

  @override
  Map<String, dynamic> get context => {
        'path': path,
        'operation': operation,
      };

  factory FileSystemError.notFound(String path) => FileSystemError(
        message: 'File not found: $path',
        path: path,
        operation: 'read',
        errorId: 'file_not_found',
        suggestion: 'Check the file path and try again.',
      );

  factory FileSystemError.accessDenied(String path) => FileSystemError(
        message: 'Access denied: $path',
        path: path,
        operation: 'access',
        errorId: 'access_denied',
        suggestion: 'Check file permissions.',
      );

  factory FileSystemError.tooLarge(String path, int size) => FileSystemError(
        message: 'File too large: $path (${_formatBytes(size)})',
        path: path,
        operation: 'read',
        errorId: 'file_too_large',
        suggestion: 'Read specific sections with offset and limit.',
      );
}

/// Configuration errors.
class ConfigError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final String? configPath;

  ConfigError({
    required this.message,
    this.configPath,
    this.errorId = 'config_error',
    this.suggestion,
  });

  @override
  Map<String, dynamic> get context => {
        if (configPath != null) 'configPath': configPath,
      };
}

/// Network errors.
class NetworkError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final String? url;

  NetworkError({
    required this.message,
    this.url,
    this.errorId = 'network_error',
    this.suggestion = 'Check your internet connection.',
  });

  @override
  Map<String, dynamic> get context => {
        if (url != null) 'url': url,
      };
}

/// Session errors.
class SessionError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final String? sessionId;

  SessionError({
    required this.message,
    this.sessionId,
    this.errorId = 'session_error',
    this.suggestion,
  });

  @override
  Map<String, dynamic> get context => {
        if (sessionId != null) 'sessionId': sessionId,
      };
}

/// Sandbox violation.
class SandboxError extends ClawError {
  @override
  final String message;
  @override
  final String errorId;
  @override
  final String? suggestion;
  final String command;
  final String reason;

  SandboxError({
    required this.command,
    required this.reason,
    this.message = 'Blocked by sandbox.',
    this.errorId = 'sandbox_violation',
    this.suggestion,
  });

  @override
  Map<String, dynamic> get context => {
        'command': command,
        'reason': reason,
      };
}

// ─── Error handler ───

/// Global error handler with recovery suggestions and reporting.
class ErrorHandler {
  final List<ErrorReport> _reports = [];
  final StreamController<ErrorReport> _errorStream =
      StreamController.broadcast();
  final int _maxReports;

  ErrorHandler({int maxReports = 100}) : _maxReports = maxReports;

  /// Stream of error reports.
  Stream<ErrorReport> get errors => _errorStream.stream;

  /// All collected reports.
  List<ErrorReport> get reports => List.unmodifiable(_reports);

  /// Handle an error, creating a report and suggesting recovery.
  ErrorReport handle(Object error, [StackTrace? stackTrace]) {
    final report = ErrorReport(
      error: error,
      stackTrace: stackTrace,
      timestamp: DateTime.now(),
      recovery: _suggestRecovery(error),
      severity: _classifySeverity(error),
    );

    _reports.add(report);
    if (_reports.length > _maxReports) {
      _reports.removeAt(0);
    }
    _errorStream.add(report);

    return report;
  }

  /// Suggest recovery action for an error.
  RecoveryAction _suggestRecovery(Object error) {
    if (error is ApiError) {
      if (error.statusCode == 401) {
        return RecoveryAction(
          label: 'Re-authenticate',
          description: 'Your API key is invalid. Run /login to set a new one.',
          action: RecoveryType.reauthenticate,
        );
      }
      if (error.statusCode == 429 || error.statusCode == 529) {
        return RecoveryAction(
          label: 'Retry',
          description: 'Wait a moment and try again.',
          action: RecoveryType.retry,
          delayMs: error.statusCode == 429 ? 5000 : 15000,
        );
      }
      if (error.isRetryable) {
        return RecoveryAction(
          label: 'Retry',
          description: 'Temporary error. Retrying...',
          action: RecoveryType.retry,
        );
      }
    }

    if (error is NetworkError) {
      return RecoveryAction(
        label: 'Check connection',
        description: 'Check your internet connection and try again.',
        action: RecoveryType.retry,
      );
    }

    if (error is FileSystemError) {
      return RecoveryAction(
        label: 'Check path',
        description: error.suggestion ?? 'Verify the file path exists.',
        action: RecoveryType.modifyInput,
      );
    }

    if (error is ConfigError) {
      return RecoveryAction(
        label: 'Fix config',
        description: error.suggestion ?? 'Check your configuration.',
        action: RecoveryType.reconfigure,
      );
    }

    return RecoveryAction(
      label: 'Dismiss',
      description: 'An unexpected error occurred.',
      action: RecoveryType.dismiss,
    );
  }

  /// Classify error severity.
  ErrorSeverity _classifySeverity(Object error) {
    if (error is ApiError) {
      if (error.statusCode == 401) return ErrorSeverity.critical;
      if (error.isRetryable) return ErrorSeverity.warning;
      return ErrorSeverity.error;
    }
    if (error is SandboxError) return ErrorSeverity.warning;
    if (error is PermissionError) return ErrorSeverity.info;
    if (error is ToolError) return ErrorSeverity.warning;
    if (error is NetworkError) return ErrorSeverity.error;
    return ErrorSeverity.error;
  }

  /// Format error for display.
  String formatError(Object error) {
    if (error is ClawError) {
      final buffer = StringBuffer();
      buffer.writeln(error.message);
      if (error.suggestion != null) {
        buffer.writeln('\nSuggestion: ${error.suggestion}');
      }
      return buffer.toString();
    }
    return error.toString();
  }

  /// Export error reports as JSON.
  String exportReports() {
    final data = _reports.map((r) => r.toJson()).toList();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Save error reports to file.
  Future<void> saveReports(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(exportReports());
  }

  /// Clear all reports.
  void clear() => _reports.clear();

  /// Dispose resources.
  void dispose() => _errorStream.close();
}

/// Error report.
class ErrorReport {
  final Object error;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final RecoveryAction recovery;
  final ErrorSeverity severity;

  const ErrorReport({
    required this.error,
    this.stackTrace,
    required this.timestamp,
    required this.recovery,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
        'error': error.toString(),
        'type': error.runtimeType.toString(),
        'timestamp': timestamp.toIso8601String(),
        'severity': severity.name,
        'recovery': recovery.label,
        if (error is ClawError) 'errorId': (error as ClawError).errorId,
        if (error is ClawError)
          'context': (error as ClawError).context,
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      };
}

/// Recovery action suggestion.
class RecoveryAction {
  final String label;
  final String description;
  final RecoveryType action;
  final int? delayMs;

  const RecoveryAction({
    required this.label,
    required this.description,
    required this.action,
    this.delayMs,
  });
}

/// Types of recovery actions.
enum RecoveryType {
  retry,
  reauthenticate,
  reconfigure,
  modifyInput,
  dismiss,
  restart,
}

/// Error severity levels.
enum ErrorSeverity { info, warning, error, critical }

// ─── Diagnostics ───

/// System health check.
class DiagnosticCheck {
  final String name;
  final String? description;
  final DiagnosticStatus status;
  final String? detail;
  final Duration? duration;

  const DiagnosticCheck({
    required this.name,
    this.description,
    required this.status,
    this.detail,
    this.duration,
  });
}

enum DiagnosticStatus { pass, warn, fail, skip }

/// Run all diagnostic checks.
Future<List<DiagnosticCheck>> runDiagnostics() async {
  final checks = <DiagnosticCheck>[];

  // Check Dart/Flutter
  checks.add(await _checkCommand('dart', ['--version'], 'Dart SDK'));

  // Check git
  checks.add(await _checkCommand('git', ['--version'], 'Git'));

  // Check network
  checks.add(await _checkNetwork());

  // Check API key
  checks.add(_checkApiKey());

  // Check disk space
  checks.add(await _checkDiskSpace());

  // Check config
  checks.add(await _checkConfig());

  // Check ripgrep (rg)
  checks.add(await _checkCommand('rg', ['--version'], 'Ripgrep'));

  return checks;
}

Future<DiagnosticCheck> _checkCommand(
    String cmd, List<String> args, String label) async {
  final sw = Stopwatch()..start();
  try {
    final result = await Process.run(cmd, args);
    sw.stop();
    if (result.exitCode == 0) {
      final version = (result.stdout as String).trim().split('\n').first;
      return DiagnosticCheck(
        name: label,
        status: DiagnosticStatus.pass,
        detail: version,
        duration: sw.elapsed,
      );
    }
    return DiagnosticCheck(
      name: label,
      status: DiagnosticStatus.warn,
      detail: 'Exit code ${result.exitCode}',
      duration: sw.elapsed,
    );
  } catch (_) {
    sw.stop();
    return DiagnosticCheck(
      name: label,
      status: DiagnosticStatus.fail,
      detail: '$cmd not found in PATH',
      duration: sw.elapsed,
    );
  }
}

Future<DiagnosticCheck> _checkNetwork() async {
  final sw = Stopwatch()..start();
  try {
    final result = await InternetAddress.lookup('api.anthropic.com')
        .timeout(const Duration(seconds: 5));
    sw.stop();
    return DiagnosticCheck(
      name: 'Network',
      status: result.isNotEmpty
          ? DiagnosticStatus.pass
          : DiagnosticStatus.fail,
      detail: result.isNotEmpty
          ? 'Connected (${result.first.address})'
          : 'Cannot resolve api.anthropic.com',
      duration: sw.elapsed,
    );
  } catch (e) {
    sw.stop();
    return DiagnosticCheck(
      name: 'Network',
      status: DiagnosticStatus.fail,
      detail: 'Cannot connect: $e',
      duration: sw.elapsed,
    );
  }
}

DiagnosticCheck _checkApiKey() {
  final key = Platform.environment['ANTHROPIC_API_KEY'];
  if (key != null && key.isNotEmpty) {
    final masked = '${key.substring(0, 8)}...${key.substring(key.length - 4)}';
    return DiagnosticCheck(
      name: 'API Key',
      status: DiagnosticStatus.pass,
      detail: 'ANTHROPIC_API_KEY set ($masked)',
    );
  }
  // Check OpenAI key as fallback
  final oaiKey = Platform.environment['OPENAI_API_KEY'];
  if (oaiKey != null && oaiKey.isNotEmpty) {
    return DiagnosticCheck(
      name: 'API Key',
      status: DiagnosticStatus.pass,
      detail: 'OPENAI_API_KEY set',
    );
  }
  return DiagnosticCheck(
    name: 'API Key',
    status: DiagnosticStatus.warn,
    detail: 'No API key found. Set ANTHROPIC_API_KEY or use /login.',
  );
}

Future<DiagnosticCheck> _checkDiskSpace() async {
  try {
    final result = await Process.run('df', ['-h', '.']);
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length >= 2) {
      final parts = lines[1].split(RegExp(r'\s+'));
      final available = parts.length > 3 ? parts[3] : 'unknown';
      final usePercent = parts.length > 4 ? parts[4] : 'unknown';
      final pct = int.tryParse(usePercent.replaceAll('%', '')) ?? 0;
      return DiagnosticCheck(
        name: 'Disk Space',
        status: pct > 95
            ? DiagnosticStatus.fail
            : pct > 85
                ? DiagnosticStatus.warn
                : DiagnosticStatus.pass,
        detail: '$available available ($usePercent used)',
      );
    }
    return DiagnosticCheck(
      name: 'Disk Space',
      status: DiagnosticStatus.skip,
      detail: 'Could not parse df output',
    );
  } catch (_) {
    return DiagnosticCheck(
      name: 'Disk Space',
      status: DiagnosticStatus.skip,
      detail: 'df not available',
    );
  }
}

Future<DiagnosticCheck> _checkConfig() async {
  final home = Platform.environment['HOME'] ?? '';
  final configDir = Directory('/.neomclaw');
  if (await configDir.exists()) {
    final settings = File('$home/.neomclaw/settings.json');
    if (await settings.exists()) {
      return DiagnosticCheck(
        name: 'Configuration',
        status: DiagnosticStatus.pass,
        detail: 'Config directory exists with settings.json',
      );
    }
    return DiagnosticCheck(
      name: 'Configuration',
      status: DiagnosticStatus.warn,
      detail: 'Config directory exists but no settings.json',
    );
  }
  return DiagnosticCheck(
    name: 'Configuration',
    status: DiagnosticStatus.warn,
    detail: 'No ~/.neomclaw directory. Run /init to create one.',
  );
}

// ─── Helpers ───

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

Map<String, dynamic>? _tryParseJson(String input) {
  try {
    return jsonDecode(input) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// Install a global error handler for uncaught errors.
void installGlobalErrorHandler(ErrorHandler handler) {
  // Zone-based error catching — use runZonedGuarded to intercept uncaught errors.
  runZonedGuarded(
    () {},
    (Object error, StackTrace stackTrace) {
      handler.handle(error, stackTrace);
    },
  );
}

/// Format a diagnostic report for display.
String formatDiagnosticReport(List<DiagnosticCheck> checks) {
  final buffer = StringBuffer();
  buffer.writeln('System Diagnostics');
  buffer.writeln('${'=' * 40}');

  for (final check in checks) {
    final icon = switch (check.status) {
      DiagnosticStatus.pass => '✓',
      DiagnosticStatus.warn => '⚠',
      DiagnosticStatus.fail => '✗',
      DiagnosticStatus.skip => '○',
    };
    buffer.write('$icon ${check.name}');
    if (check.detail != null) {
      buffer.write(': ${check.detail}');
    }
    if (check.duration != null) {
      buffer.write(' (${check.duration!.inMilliseconds}ms)');
    }
    buffer.writeln();
  }

  final passed = checks.where((c) => c.status == DiagnosticStatus.pass).length;
  final warned = checks.where((c) => c.status == DiagnosticStatus.warn).length;
  final failed = checks.where((c) => c.status == DiagnosticStatus.fail).length;

  buffer.writeln('${'=' * 40}');
  buffer.writeln('$passed passed, $warned warnings, $failed failed');

  return buffer.toString();
}
