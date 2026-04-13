/// Policy that controls how aggressively context is compacted during
/// queued compaction processing.
enum CompactionPolicy {
  /// Aggressive compaction — removes all non-essential content, keeps only
  /// key conclusions and decisions.
  strict('Removes all non-essential content, keeps only key conclusions and decisions.'),

  /// Moderate compaction — preserves reasoning chains and important context
  /// while reducing verbosity.
  lenient('Preserves reasoning chains and important context while reducing verbosity.'),

  /// User-defined compaction rules with custom preservation patterns.
  custom('User-defined compaction rules with custom preservation patterns.');

  /// Human-readable description of what this policy does.
  final String description;

  const CompactionPolicy(this.description);
}
