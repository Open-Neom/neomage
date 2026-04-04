// Analytics service — port of neom_claw/src/services/analytics.
// Event logging, sinks, feature flags, and session metrics.

/// Analytics event with metadata.
class AnalyticsEvent {
  final String name;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  AnalyticsEvent({
    required this.name,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Sink interface for routing analytics events.
abstract class AnalyticsSink {
  /// Whether this sink is enabled.
  bool get isEnabled;

  /// Send an event to this sink.
  Future<void> logEvent(AnalyticsEvent event);

  /// Flush pending events.
  Future<void> flush();

  /// Dispose resources.
  Future<void> dispose();
}

/// In-memory analytics sink for local debugging.
class InMemoryAnalyticsSink implements AnalyticsSink {
  final List<AnalyticsEvent> events = [];
  bool _enabled = true;

  @override
  bool get isEnabled => _enabled;

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    if (_enabled) events.add(event);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> dispose() async {
    _enabled = false;
  }

  /// Get events by name.
  List<AnalyticsEvent> getByName(String name) =>
      events.where((e) => e.name == name).toList();

  /// Clear all events.
  void clear() => events.clear();
}

/// File-based analytics sink for offline storage.
class FileAnalyticsSink implements AnalyticsSink {
  final String filePath;
  final List<AnalyticsEvent> _buffer = [];
  final int maxBufferSize;
  bool _enabled = true;

  FileAnalyticsSink({
    required this.filePath,
    this.maxBufferSize = 100,
  });

  @override
  bool get isEnabled => _enabled;

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    _buffer.add(event);
    if (_buffer.length >= maxBufferSize) {
      await flush();
    }
  }

  @override
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    // Write buffered events to file
    // In production, this would append to JSONL file
    _buffer.clear();
  }

  @override
  Future<void> dispose() async {
    await flush();
    _enabled = false;
  }
}

/// Central analytics service — manages sinks and event routing.
class AnalyticsService {
  final List<AnalyticsSink> _sinks = [];
  final List<AnalyticsEvent> _preAttachQueue = [];
  bool _attached = false;

  /// Attach a sink for event routing.
  void attachSink(AnalyticsSink sink) {
    _sinks.add(sink);
    if (!_attached) {
      _attached = true;
      // Drain pre-attach queue
      for (final event in _preAttachQueue) {
        _routeEvent(event);
      }
      _preAttachQueue.clear();
    }
  }

  /// Log an event synchronously (queued if no sink attached yet).
  void logEvent(String name, [Map<String, dynamic> metadata = const {}]) {
    final event = AnalyticsEvent(name: name, metadata: metadata);
    if (!_attached) {
      _preAttachQueue.add(event);
      return;
    }
    _routeEvent(event);
  }

  /// Log an event asynchronously.
  Future<void> logEventAsync(
    String name, [
    Map<String, dynamic> metadata = const {},
  ]) async {
    final event = AnalyticsEvent(name: name, metadata: metadata);
    if (!_attached) {
      _preAttachQueue.add(event);
      return;
    }
    await _routeEventAsync(event);
  }

  void _routeEvent(AnalyticsEvent event) {
    for (final sink in _sinks) {
      if (sink.isEnabled) {
        sink.logEvent(event); // fire and forget
      }
    }
  }

  Future<void> _routeEventAsync(AnalyticsEvent event) async {
    for (final sink in _sinks) {
      if (sink.isEnabled) {
        await sink.logEvent(event);
      }
    }
  }

  /// Flush all sinks.
  Future<void> flush() async {
    for (final sink in _sinks) {
      await sink.flush();
    }
  }

  /// Dispose all sinks.
  Future<void> dispose() async {
    for (final sink in _sinks) {
      await sink.dispose();
    }
    _sinks.clear();
  }
}

/// Well-known analytics event names.
class AnalyticsEvents {
  static const sessionInit = 'session_init';
  static const sessionExit = 'session_exit';
  static const apiSuccess = 'api_success';
  static const apiError = 'api_error';
  static const toolUseGranted = 'tool_use_granted';
  static const toolUseRejected = 'tool_use_rejected';
  static const toolUseSuccess = 'tool_use_success';
  static const toolUseError = 'tool_use_error';
  static const commandExecuted = 'command_executed';
  static const compactionTriggered = 'compaction_triggered';
  static const memoryWritten = 'memory_written';
  static const oauthTokenRefresh = 'oauth_token_refresh';
  static const modelFallback = 'model_fallback';
  static const tipShown = 'tip_shown';
  static const promptSuggestionAccepted = 'prompt_suggestion_accepted';
  static const promptSuggestionIgnored = 'prompt_suggestion_ignored';
}
