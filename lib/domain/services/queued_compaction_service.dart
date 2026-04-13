/// Abstract interface for queued context compaction.
///
/// Sessions are enqueued for compaction and processed in batch. Preemptive
/// compaction triggers when the token budget reaches 80% capacity.
abstract class QueuedCompactionService {
  /// Marks a session for compaction by adding it to the processing queue.
  void enqueue(String sessionId);

  /// Processes all pending compactions in the queue.
  ///
  /// Returns the number of sessions successfully compacted.
  int processQueue();

  /// Returns `true` if preemptive compaction should trigger.
  ///
  /// The threshold is 80% of [maxTokens].
  bool shouldCompactPreemptively(int currentTokens, int maxTokens);
}
