import 'dart:async';

import '../../domain/models/diagnostic_activity.dart';
import '../../domain/models/diagnostic_event.dart';
import '../../domain/services/diagnostic_runtime_service.dart';

/// Default diagnostic runtime implementation with in-memory tracking.
class DiagnosticRuntimeServiceImpl implements DiagnosticRuntimeService {
  final _activities = <String, _ActivityState>{};
  final _eventController = StreamController<DiagnosticEvent>.broadcast();

  /// Maximum events to buffer per component.
  final int maxBufferedEvents;

  DiagnosticRuntimeServiceImpl({this.maxBufferedEvents = 1000});

  @override
  void emit(DiagnosticEvent event) {
    _eventController.add(event);
    markActivity(event.source);
  }

  @override
  void markActivity(String componentId) {
    final state = _activities.putIfAbsent(componentId, _ActivityState.new);
    state.lastActivityAt = DateTime.now();
    state.totalEvents++;
  }

  @override
  DateTime? getLastActivityAt(String componentId) {
    return _activities[componentId]?.lastActivityAt;
  }

  @override
  List<DiagnosticActivity> getActivitySummary() {
    return _activities.entries.map((e) {
      return DiagnosticActivity(
        componentId: e.key,
        lastActivityAt: e.value.lastActivityAt,
        totalEvents: e.value.totalEvents,
        queueDepth: e.value.queueDepth,
      );
    }).toList();
  }

  @override
  void logLaneEnqueue(String lane, {Map<String, dynamic>? metadata}) {
    final state = _activities.putIfAbsent(lane, _ActivityState.new);
    state.queueDepth++;
    emit(DiagnosticEvent(
      type: 'queue.lane.enqueue',
      source: lane,
      timestamp: DateTime.now(),
      data: {'depth': state.queueDepth, ...?metadata},
    ));
  }

  @override
  void logLaneDequeue(String lane, {Map<String, dynamic>? metadata}) {
    final state = _activities[lane];
    if (state != null && state.queueDepth > 0) {
      state.queueDepth--;
    }
    emit(DiagnosticEvent(
      type: 'queue.lane.dequeue',
      source: lane,
      timestamp: DateTime.now(),
      data: {'depth': state?.queueDepth ?? 0, ...?metadata},
    ));
  }

  @override
  Stream<DiagnosticEvent> get eventStream => _eventController.stream;

  void dispose() {
    _eventController.close();
  }
}

class _ActivityState {
  DateTime lastActivityAt = DateTime.now();
  int totalEvents = 0;
  int queueDepth = 0;
}
