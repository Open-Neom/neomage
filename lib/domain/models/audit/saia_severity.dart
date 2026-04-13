/// Severity level for audit checks.
///
/// Each severity carries a weight multiplier that determines
/// its impact on the overall health score.
enum SaiaSeverity {
  /// Immediate revenue/data loss risk. Fix immediately.
  critical(5.0),

  /// Significant performance drag. Fix within 7 days.
  high(3.0),

  /// Optimization opportunity. Address within 30 days.
  medium(1.5),

  /// Best practice, minor impact. Nice to have.
  low(0.5);

  /// Weight multiplier used in scoring calculations.
  final double weight;

  const SaiaSeverity(this.weight);
}
