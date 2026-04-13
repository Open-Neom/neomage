/// A structured diagnostic event emitted during agent operations.
class DiagnosticEvent {
  /// Event type identifier (e.g., 'queue.lane.enqueue', 'tool.execute').
  final String type;

  /// Event payload with contextual data.
  final Map<String, dynamic> data;

  /// Timestamp of the event.
  final DateTime timestamp;

  /// Severity level.
  final DiagnosticSeverity severity;

  /// Source component that emitted the event.
  final String source;

  const DiagnosticEvent({
    required this.type,
    this.data = const {},
    required this.timestamp,
    this.severity = DiagnosticSeverity.info,
    this.source = 'unknown',
  });
}

enum DiagnosticSeverity {
  debug,
  info,
  warning,
  error,
}
