import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'dart:math';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Categories of telemetry events emitted throughout the application.
enum TelemetryEventType {
  toolUse,
  apiCall,
  commandRun,
  error,
  sessionStart,
  sessionEnd,
  permissionGrant,
  permissionDeny,
  modelSwitch,
  compaction,
  memoryWrite,
  mcpConnect,
  hookRun,
  featureFlag,
  performance,
}

// ---------------------------------------------------------------------------
// TelemetryEvent
// ---------------------------------------------------------------------------

/// A single telemetry event with associated metadata.
class TelemetryEvent {
  TelemetryEvent({
    required this.name,
    required this.type,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
    String? sessionId,
  }) : properties = properties ?? <String, dynamic>{},
       timestamp = timestamp ?? DateTime.now(),
       sessionId = sessionId ?? '';

  final String name;
  final TelemetryEventType type;
  final Map<String, dynamic> properties;
  final DateTime timestamp;
  final String sessionId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'type': type.name,
    'properties': properties,
    'timestamp': timestamp.toIso8601String(),
    'sessionId': sessionId,
  };

  factory TelemetryEvent.fromJson(Map<String, dynamic> json) {
    return TelemetryEvent(
      name: json['name'] as String,
      type: TelemetryEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TelemetryEventType.error,
      ),
      properties: (json['properties'] as Map<String, dynamic>?) ?? {},
      timestamp: DateTime.parse(json['timestamp'] as String),
      sessionId: (json['sessionId'] as String?) ?? '',
    );
  }

  @override
  String toString() => 'TelemetryEvent($name, ${type.name})';
}

// ---------------------------------------------------------------------------
// TelemetryBatch
// ---------------------------------------------------------------------------

/// Collects events into a batch for efficient bulk sending.
class TelemetryBatch {
  TelemetryBatch({int maxSize = 100}) : _maxSize = maxSize;

  final int _maxSize;
  final List<TelemetryEvent> _events = [];
  DateTime? _firstEventTime;

  /// Number of events currently in the batch.
  int get length => _events.length;

  /// Whether the batch has reached its maximum capacity.
  bool get isFull => _events.length >= _maxSize;

  /// Whether the batch contains no events.
  bool get isEmpty => _events.isEmpty;

  /// Age of the batch measured from the first event added.
  Duration get age {
    if (_firstEventTime == null) return Duration.zero;
    return DateTime.now().difference(_firstEventTime!);
  }

  /// Add an event to the batch. Returns `true` when the batch is now full.
  bool add(TelemetryEvent event) {
    _firstEventTime ??= DateTime.now();
    _events.add(event);
    return isFull;
  }

  /// Drain all events and reset internal state.
  List<TelemetryEvent> drain() {
    final drained = List<TelemetryEvent>.from(_events);
    _events.clear();
    _firstEventTime = null;
    return drained;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'events': _events.map((e) => e.toJson()).toList(),
    'count': _events.length,
    'firstEventTime': _firstEventTime?.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// TelemetrySink (abstract)
// ---------------------------------------------------------------------------

/// Destination for telemetry events.
abstract class TelemetrySink {
  /// Human-readable name of this sink.
  String get name;

  /// Send a batch of events. Returns `true` on success.
  Future<bool> send(List<TelemetryEvent> events);

  /// Perform any necessary cleanup.
  Future<void> dispose();
}

// ---------------------------------------------------------------------------
// ConsoleTelemetrySink
// ---------------------------------------------------------------------------

/// Prints telemetry events to stderr when running in debug mode.
class ConsoleTelemetrySink implements TelemetrySink {
  ConsoleTelemetrySink({this.verbose = false});

  final bool verbose;

  @override
  String get name => 'console';

  @override
  Future<bool> send(List<TelemetryEvent> events) async {
    // Only emit output when running with assertions enabled (debug mode).
    bool isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    if (!isDebug) return true;

    for (final event in events) {
      if (verbose) {
        stderr.writeln('[telemetry] ${jsonEncode(event.toJson())}');
      } else {
        stderr.writeln('[telemetry] ${event.type.name}: ${event.name}');
      }
    }
    return true;
  }

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// FileTelemetrySink
// ---------------------------------------------------------------------------

/// Appends events as newline-delimited JSON to a file inside
/// `~/.neomage/telemetry/`.
class FileTelemetrySink implements TelemetrySink {
  FileTelemetrySink({String? directory})
    : _directory =
          directory ??
          '${Platform.environment['HOME'] ?? '/tmp'}/.neomage/telemetry';

  final String _directory;
  IOSink? _sink;
  String? _currentFilePath;

  @override
  String get name => 'file';

  String _filePathForToday() {
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return '$_directory/telemetry-$date.jsonl';
  }

  Future<IOSink> _getOrCreateSink() async {
    final path = _filePathForToday();
    if (_sink != null && _currentFilePath == path) return _sink!;

    // Close previous sink if the date rolled over.
    await _sink?.flush();
    await _sink?.close();

    final dir = Directory(_directory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File(path);
    _sink = file.openWrite(mode: FileMode.append);
    _currentFilePath = path;
    return _sink!;
  }

  @override
  Future<bool> send(List<TelemetryEvent> events) async {
    try {
      final sink = await _getOrCreateSink();
      for (final event in events) {
        sink.writeln(jsonEncode(event.toJson()));
      }
      await sink.flush();
      return true;
    } catch (e) {
      stderr.writeln('[telemetry:file] write error: $e');
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

// ---------------------------------------------------------------------------
// HttpTelemetrySink
// ---------------------------------------------------------------------------

/// Posts event batches to a remote HTTP endpoint.
class HttpTelemetrySink implements TelemetrySink {
  HttpTelemetrySink({
    String? endpoint,
    this.timeoutSeconds = 10,
    this.authToken,
    this.maxRetries = 2,
  }) : endpoint =
           endpoint ?? 'https://telemetry.neomage.ai/v1/events'; // stub URL

  final String endpoint;
  final int timeoutSeconds;
  final String? authToken;
  final int maxRetries;
  HttpClient? _client;

  @override
  String get name => 'http';

  HttpClient get _httpClient => _client ??= HttpClient();

  @override
  Future<bool> send(List<TelemetryEvent> events) async {
    final payload = jsonEncode({
      'events': events.map((e) => e.toJson()).toList(),
      'sentAt': DateTime.now().toIso8601String(),
    });

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final uri = Uri.parse(endpoint);
        final request = await _httpClient
            .postUrl(uri)
            .timeout(Duration(seconds: timeoutSeconds));
        request.headers.set('Content-Type', 'application/json');
        if (authToken != null) {
          request.headers.set('Authorization', 'Bearer $authToken');
        }
        request.write(payload);

        final response = await request.close().timeout(
          Duration(seconds: timeoutSeconds),
        );
        // Drain the response body so the connection can be reused.
        await response.drain<void>();

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return true;
        }
        // Retry on server errors only.
        if (response.statusCode < 500) return false;
      } on TimeoutException {
        // Fall through to retry.
      } on SocketException {
        // Network unreachable — retry.
      } catch (e) {
        stderr.writeln('[telemetry:http] send error: $e');
        return false;
      }

      // Exponential back-off before retrying.
      if (attempt < maxRetries) {
        await Future<void>.delayed(
          Duration(milliseconds: 200 * (1 << attempt)),
        );
      }
    }
    return false;
  }

  @override
  Future<void> dispose() async {
    _client?.close(force: true);
    _client = null;
  }
}

// ---------------------------------------------------------------------------
// PII Scrubbing
// ---------------------------------------------------------------------------

/// Regular expressions for personally-identifiable information.
final RegExp _emailRegex = RegExp(
  r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
);
final RegExp _apiKeyRegex = RegExp(
  r'(?:sk-|api[_-]?key[_-]?|token[_-]?|secret[_-]?)[a-zA-Z0-9_\-]{16,}',
  caseSensitive: false,
);

/// Scrub PII from a map of telemetry properties.
///
/// Replaces email addresses, API keys / tokens, and absolute file paths that
/// contain the user's home directory with redacted placeholders.
Map<String, dynamic> scrubPii(Map<String, dynamic> data, {String? homeDir}) {
  final home = homeDir ?? Platform.environment['HOME'] ?? '/home/user';
  final result = <String, dynamic>{};

  for (final entry in data.entries) {
    final value = entry.value;
    if (value is String) {
      result[entry.key] = _scrubString(value, home);
    } else if (value is Map<String, dynamic>) {
      result[entry.key] = scrubPii(value, homeDir: home);
    } else if (value is List) {
      result[entry.key] = value.map((v) {
        if (v is String) return _scrubString(v, home);
        if (v is Map<String, dynamic>) return scrubPii(v, homeDir: home);
        return v;
      }).toList();
    } else {
      result[entry.key] = value;
    }
  }
  return result;
}

String _scrubString(String input, String home) {
  var s = input;
  s = s.replaceAll(_emailRegex, '[EMAIL_REDACTED]');
  s = s.replaceAll(_apiKeyRegex, '[API_KEY_REDACTED]');
  if (home.isNotEmpty) {
    s = s.replaceAll(home, '~');
  }
  return s;
}

// ---------------------------------------------------------------------------
// PerformanceTracker
// ---------------------------------------------------------------------------

/// Measures wall-clock duration of arbitrary operations.
class PerformanceTracker {
  final Map<String, _TimerEntry> _running = {};
  final List<PerformanceMetric> _completed = [];

  /// Start tracking an operation identified by [operationId].
  void start(String operationId, {Map<String, dynamic>? metadata}) {
    _running[operationId] = _TimerEntry(
      startTime: DateTime.now(),
      metadata: metadata ?? {},
    );
  }

  /// Stop tracking and return the elapsed duration.
  /// Returns `null` if [operationId] was not being tracked.
  Duration? stop(String operationId, {Map<String, dynamic>? extraMetadata}) {
    final entry = _running.remove(operationId);
    if (entry == null) return null;

    final duration = DateTime.now().difference(entry.startTime);
    final merged = <String, dynamic>{
      ...entry.metadata,
      if (extraMetadata != null) ...extraMetadata,
    };
    _completed.add(
      PerformanceMetric(
        operationId: operationId,
        duration: duration,
        startTime: entry.startTime,
        metadata: merged,
      ),
    );
    return duration;
  }

  /// Retrieve all completed metrics and clear the internal list.
  List<PerformanceMetric> drain() {
    final metrics = List<PerformanceMetric>.from(_completed);
    _completed.clear();
    return metrics;
  }

  /// Whether any operations are currently being tracked.
  bool get hasRunning => _running.isNotEmpty;

  /// Number of completed (but not yet drained) metrics.
  int get completedCount => _completed.length;
}

class _TimerEntry {
  _TimerEntry({required this.startTime, required this.metadata});
  final DateTime startTime;
  final Map<String, dynamic> metadata;
}

/// Result of a timed operation.
class PerformanceMetric {
  PerformanceMetric({
    required this.operationId,
    required this.duration,
    required this.startTime,
    this.metadata = const {},
  });

  final String operationId;
  final Duration duration;
  final DateTime startTime;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'durationMs': duration.inMilliseconds,
    'startTime': startTime.toIso8601String(),
    'metadata': metadata,
  };
}

// ---------------------------------------------------------------------------
// TelemetryConfig
// ---------------------------------------------------------------------------

/// Configuration for the telemetry subsystem.
class TelemetryConfig {
  TelemetryConfig({
    this.enabled = true,
    this.scrubPiiEnabled = true,
    this.batchSize = 100,
    this.flushIntervalSeconds = 30,
    List<TelemetrySink>? sinks,
    Set<TelemetryEventType>? disabledEventTypes,
  }) : sinks = sinks ?? [],
       disabledEventTypes = disabledEventTypes ?? {};

  /// Master switch for all telemetry collection.
  bool enabled;

  /// When true, PII is scrubbed from event properties before sending.
  bool scrubPiiEnabled;

  /// Maximum number of events per batch before an automatic flush.
  int batchSize;

  /// Interval in seconds between automatic flushes.
  int flushIntervalSeconds;

  /// Sinks that receive event batches.
  final List<TelemetrySink> sinks;

  /// Event types that should be silently dropped.
  final Set<TelemetryEventType> disabledEventTypes;

  /// Create a sensible default configuration for development.
  factory TelemetryConfig.development() => TelemetryConfig(
    enabled: true,
    scrubPiiEnabled: true,
    batchSize: 50,
    flushIntervalSeconds: 10,
    sinks: [ConsoleTelemetrySink(verbose: true)],
  );

  /// Create a production configuration with file + HTTP sinks.
  factory TelemetryConfig.production({
    String? httpEndpoint,
    String? authToken,
  }) {
    return TelemetryConfig(
      enabled: true,
      scrubPiiEnabled: true,
      batchSize: 100,
      flushIntervalSeconds: 30,
      sinks: [
        FileTelemetrySink(),
        HttpTelemetrySink(endpoint: httpEndpoint, authToken: authToken),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TelemetryService
// ---------------------------------------------------------------------------

/// Central telemetry service. Queue events via [track], they are flushed to
/// all configured sinks either on a timer or when the batch fills up.
class TelemetryService {
  TelemetryService({required TelemetryConfig config})
    : _config = config,
      _batch = TelemetryBatch(maxSize: config.batchSize),
      _performanceTracker = PerformanceTracker(),
      _sessionId = _generateSessionId() {
    if (_config.enabled) {
      _startAutoFlush();
    }
  }

  final TelemetryConfig _config;
  final TelemetryBatch _batch;
  final PerformanceTracker _performanceTracker;
  final String _sessionId;
  Timer? _flushTimer;
  bool _disposed = false;
  bool _sessionStarted = false;
  int _totalTracked = 0;
  int _totalFlushed = 0;
  int _totalDropped = 0;

  /// Unique session identifier.
  String get sessionId => _sessionId;

  /// Access the performance tracker for timing operations.
  PerformanceTracker get performance => _performanceTracker;

  /// Statistics about this service instance.
  Map<String, int> get stats => {
    'tracked': _totalTracked,
    'flushed': _totalFlushed,
    'dropped': _totalDropped,
    'pending': _batch.length,
  };

  // ---- Session lifecycle ---------------------------------------------------

  /// Record a session-start event.
  void startSession({Map<String, dynamic>? metadata}) {
    if (_sessionStarted) return;
    _sessionStarted = true;
    track(
      TelemetryEvent(
        name: 'session_start',
        type: TelemetryEventType.sessionStart,
        properties: {
          'platform': Platform.operatingSystem,
          'dartVersion': Platform.version.split(' ').first,
          if (metadata != null) ...metadata,
        },
        sessionId: _sessionId,
      ),
    );
  }

  /// Record a session-end event and flush remaining events.
  Future<void> endSession({Map<String, dynamic>? metadata}) async {
    if (!_sessionStarted) return;

    // Drain pending performance metrics into events.
    _flushPerformanceMetrics();

    track(
      TelemetryEvent(
        name: 'session_end',
        type: TelemetryEventType.sessionEnd,
        properties: {
          'totalTracked': _totalTracked,
          'totalFlushed': _totalFlushed,
          if (metadata != null) ...metadata,
        },
        sessionId: _sessionId,
      ),
    );
    _sessionStarted = false;
    await flush();
  }

  // ---- Core tracking -------------------------------------------------------

  /// Queue a telemetry event. It will be sent on the next flush.
  void track(TelemetryEvent event) {
    if (_disposed || !_config.enabled) return;

    // Drop disabled event types silently.
    if (_config.disabledEventTypes.contains(event.type)) {
      _totalDropped++;
      return;
    }

    // Attach session id if missing.
    final enriched = TelemetryEvent(
      name: event.name,
      type: event.type,
      properties: _config.scrubPiiEnabled
          ? scrubPii(event.properties)
          : Map<String, dynamic>.from(event.properties),
      timestamp: event.timestamp,
      sessionId: event.sessionId.isEmpty ? _sessionId : event.sessionId,
    );

    _totalTracked++;
    final full = _batch.add(enriched);
    if (full) {
      // Fire-and-forget flush when batch fills up.
      unawaited(flush());
    }
  }

  // ---- Convenience trackers ------------------------------------------------

  /// Track an API call with latency.
  void trackApiCall({
    required String model,
    required Duration latency,
    int? inputTokens,
    int? outputTokens,
    String? error,
  }) {
    track(
      TelemetryEvent(
        name: 'api_call',
        type: TelemetryEventType.apiCall,
        properties: {
          'model': model,
          'latencyMs': latency.inMilliseconds,
          'inputTokens': ?inputTokens,
          'outputTokens': ?outputTokens,
          'error': ?error,
        },
      ),
    );
  }

  /// Track tool usage with duration.
  void trackToolUse({
    required String toolName,
    required Duration duration,
    bool success = true,
    String? error,
  }) {
    track(
      TelemetryEvent(
        name: 'tool_use',
        type: TelemetryEventType.toolUse,
        properties: {
          'tool': toolName,
          'durationMs': duration.inMilliseconds,
          'success': success,
          'error': ?error,
        },
      ),
    );
  }

  /// Track an error with contextual information.
  void trackError({
    required String message,
    String? stackTrace,
    String? context,
    String? errorCode,
  }) {
    track(
      TelemetryEvent(
        name: 'error',
        type: TelemetryEventType.error,
        properties: {
          'message': message,
          'stackTrace': ?stackTrace,
          'context': ?context,
          'errorCode': ?errorCode,
        },
      ),
    );
  }

  /// Track a model switch.
  void trackModelSwitch({
    required String fromModel,
    required String toModel,
    String? reason,
  }) {
    track(
      TelemetryEvent(
        name: 'model_switch',
        type: TelemetryEventType.modelSwitch,
        properties: {'from': fromModel, 'to': toModel, 'reason': ?reason},
      ),
    );
  }

  /// Track a permission decision.
  void trackPermission({
    required String tool,
    required bool granted,
    String? reason,
  }) {
    track(
      TelemetryEvent(
        name: granted ? 'permission_grant' : 'permission_deny',
        type: granted
            ? TelemetryEventType.permissionGrant
            : TelemetryEventType.permissionDeny,
        properties: {'tool': tool, 'reason': ?reason},
      ),
    );
  }

  // ---- Flushing ------------------------------------------------------------

  /// Flush all pending events to every configured sink.
  Future<void> flush() async {
    if (_batch.isEmpty) return;

    // Include any completed performance metrics as events.
    _flushPerformanceMetrics();

    final events = _batch.drain();
    if (events.isEmpty) return;

    final futures = <Future<bool>>[];
    for (final sink in _config.sinks) {
      futures.add(_sendWithErrorHandling(sink, events));
    }
    final results = await Future.wait(futures);

    final successCount = results.where((r) => r).length;
    if (successCount > 0) {
      _totalFlushed += events.length;
    } else if (_config.sinks.isNotEmpty) {
      _totalDropped += events.length;
    }
  }

  Future<bool> _sendWithErrorHandling(
    TelemetrySink sink,
    List<TelemetryEvent> events,
  ) async {
    try {
      return await sink.send(events);
    } catch (e) {
      stderr.writeln('[telemetry] sink "${sink.name}" error: $e');
      return false;
    }
  }

  void _flushPerformanceMetrics() {
    final metrics = _performanceTracker.drain();
    for (final metric in metrics) {
      _batch.add(
        TelemetryEvent(
          name: 'performance_metric',
          type: TelemetryEventType.performance,
          properties: metric.toJson(),
          sessionId: _sessionId,
        ),
      );
    }
  }

  // ---- Auto-flush timer ----------------------------------------------------

  void _startAutoFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      Duration(seconds: _config.flushIntervalSeconds),
      (_) => unawaited(flush()),
    );
  }

  // ---- Opt-out / Privacy ---------------------------------------------------

  /// Disable all telemetry collection. Pending events are flushed first.
  Future<void> optOut() async {
    _config.enabled = false;
    await flush();
    _flushTimer?.cancel();
  }

  /// Re-enable telemetry after opting out.
  void optIn() {
    _config.enabled = true;
    _startAutoFlush();
  }

  // ---- Disposal ------------------------------------------------------------

  /// Flush remaining events and release resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    await flush();
    for (final sink in _config.sinks) {
      await sink.dispose();
    }
  }

  // ---- Helpers -------------------------------------------------------------

  static String _generateSessionId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
