import '../../domain/services/queued_compaction_service.dart';

/// Concrete implementation of [QueuedCompactionService].
///
/// Maintains an in-memory FIFO queue of session IDs pending compaction.
/// Preemptive trigger fires at 80% of the token budget.
class QueuedCompactionEngine implements QueuedCompactionService {
  /// The internal queue of session IDs awaiting compaction.
  final List<String> _queue = [];

  /// Sessions that have been processed (for dedup within a lifecycle).
  final Set<String> _processed = {};

  /// Preemptive compaction threshold as a fraction of max tokens.
  static const double _preemptiveThreshold = 0.8;

  /// Returns an unmodifiable view of the current queue.
  List<String> get pendingQueue => List.unmodifiable(_queue);

  /// Returns the number of sessions processed so far.
  int get processedCount => _processed.length;

  @override
  void enqueue(String sessionId) {
    if (sessionId.isEmpty) return;
    // Avoid duplicate enqueue for sessions already queued or processed.
    if (_queue.contains(sessionId) || _processed.contains(sessionId)) return;
    _queue.add(sessionId);
  }

  @override
  int processQueue() {
    if (_queue.isEmpty) return 0;

    int count = 0;
    // Process the entire queue in batch.
    while (_queue.isNotEmpty) {
      final sessionId = _queue.removeAt(0);
      final success = _compactSession(sessionId);
      if (success) {
        _processed.add(sessionId);
        count++;
      }
    }

    return count;
  }

  @override
  bool shouldCompactPreemptively(int currentTokens, int maxTokens) {
    if (maxTokens <= 0) return false;
    return currentTokens / maxTokens >= _preemptiveThreshold;
  }

  /// Compacts a single session. Returns `true` on success.
  ///
  /// Subclasses or future implementations can override the actual compaction
  /// logic. The base implementation always succeeds.
  bool _compactSession(String sessionId) {
    // Base implementation: mark as compacted. Actual LLM-based compaction
    // would be injected or overridden by the host application.
    return true;
  }
}
