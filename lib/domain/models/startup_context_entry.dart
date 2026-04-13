/// A single memory entry loaded during startup context injection.
class StartupContextEntry {
  /// Source identifier (e.g., 'biochip', 'daily:2026-04-11', 'mission').
  final String source;

  /// The memory content to inject.
  final String content;

  /// Original byte size before truncation.
  final int originalBytes;

  /// Whether the content was truncated to fit limits.
  final bool truncated;

  /// Timestamp of the memory source.
  final DateTime? sourceTimestamp;

  const StartupContextEntry({
    required this.source,
    required this.content,
    this.originalBytes = 0,
    this.truncated = false,
    this.sourceTimestamp,
  });

  int get charCount => content.length;
}
