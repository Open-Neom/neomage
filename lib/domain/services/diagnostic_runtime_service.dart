import '../models/diagnostic_activity.dart';
import '../models/diagnostic_event.dart';

/// Service contract for structured diagnostic monitoring.
///
/// Provides activity tracking, event emission, and idle detection
/// for agent components (pipeline, tools, memory, cron).
abstract class DiagnosticRuntimeService {
  /// Emit a diagnostic event.
  void emit(DiagnosticEvent event);

  /// Mark activity for a component (resets idle timer).
  void markActivity(String componentId);

  /// Get last activity timestamp for a component.
  DateTime? getLastActivityAt(String componentId);

  /// Get activity summary for all tracked components.
  List<DiagnosticActivity> getActivitySummary();

  /// Log a queue lane enqueue operation.
  void logLaneEnqueue(String lane, {Map<String, dynamic>? metadata});

  /// Log a queue lane dequeue operation.
  void logLaneDequeue(String lane, {Map<String, dynamic>? metadata});

  /// Stream of diagnostic events for real-time monitoring.
  Stream<DiagnosticEvent> get eventStream;
}
