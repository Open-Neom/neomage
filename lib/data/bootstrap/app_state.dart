// Bootstrap app state — ported from OpenClaude src/bootstrap/state.ts.
// Centralized state for session, metrics, and configuration.

import 'package:uuid/uuid.dart';

import '../../domain/models/ids.dart';

/// Application-wide bootstrap state.
class AppState {
  // ── Session Identity ──
  SessionId sessionId;
  SessionId? parentSessionId;
  String cwd;
  String? projectRoot;
  String? originalCwd;

  // ── Cost & Metrics ──
  double totalCostUsd;
  Duration totalApiDuration;
  int totalApiCalls;
  int linesAdded;
  int linesRemoved;

  // ── Timing ──
  final DateTime startTime;
  DateTime lastInteractionTime;

  // ── Model Config ──
  String? mainLoopModelOverride;
  String? initialMainLoopModel;
  bool fastModeEnabled;

  // ── Feature Flags ──
  bool isInteractive;
  bool kairosActive;
  bool strictToolResultPairing;

  AppState._({
    required this.sessionId,
    required this.cwd,
    required this.startTime,
  })  : totalCostUsd = 0.0,
        totalApiDuration = Duration.zero,
        totalApiCalls = 0,
        linesAdded = 0,
        linesRemoved = 0,
        lastInteractionTime = startTime,
        fastModeEnabled = false,
        isInteractive = true,
        kairosActive = false,
        strictToolResultPairing = false;

  /// Create initial app state.
  factory AppState.initial({String? cwd}) {
    final uuid = const Uuid().v4();
    return AppState._(
      sessionId: SessionId(uuid),
      cwd: cwd ?? '.',
      startTime: DateTime.now(),
    );
  }

  // ── Session Management ──

  /// Switch session (atomically changes sessionId and projectDir).
  void switchSession({required String sessionId, required String projectDir}) {
    this.sessionId = SessionId(sessionId);
    projectRoot = projectDir;
    cwd = projectDir;
  }

  /// Regenerate session ID (for new sessions without changing project).
  void regenerateSessionId() {
    sessionId = SessionId(const Uuid().v4());
  }

  // ── Cost Tracking ──

  void addCost(double cost) => totalCostUsd += cost;

  void addApiDuration(Duration duration) {
    totalApiDuration += duration;
    totalApiCalls++;
  }

  // ── Code Metrics ──

  void addCodeChanges({int added = 0, int removed = 0}) {
    linesAdded += added;
    linesRemoved += removed;
  }

  // ── Interaction ──

  void markInteraction() => lastInteractionTime = DateTime.now();

  Duration get idleDuration =>
      DateTime.now().difference(lastInteractionTime);

  Duration get sessionDuration =>
      DateTime.now().difference(startTime);
}
