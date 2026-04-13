/// Tracks activity state for diagnostic monitoring.
///
/// Used to detect idle agents, stalled pipelines, and
/// measure time between operations.
class DiagnosticActivity {
  /// Component identifier.
  final String componentId;

  /// Last activity timestamp.
  final DateTime lastActivityAt;

  /// Total events emitted by this component.
  final int totalEvents;

  /// Current queue depth (if applicable).
  final int queueDepth;

  const DiagnosticActivity({
    required this.componentId,
    required this.lastActivityAt,
    this.totalEvents = 0,
    this.queueDepth = 0,
  });

  /// Duration since last activity.
  Duration get idleDuration => DateTime.now().difference(lastActivityAt);

  /// Whether the component appears stalled (> 30 seconds idle).
  bool get isStalled => idleDuration.inSeconds > 30;
}
