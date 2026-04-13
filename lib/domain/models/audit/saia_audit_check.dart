import 'saia_check_result.dart';
import 'saia_severity.dart';

/// Definition of a single audit check.
///
/// Checks are the atomic unit of the audit framework.
/// Each check belongs to a category, has a severity, and
/// produces a [SaiaCheckOutcome] when evaluated.
class SaiaAuditCheck {
  /// Unique check identifier (e.g., 'G42', 'SEC-01').
  final String id;

  /// Category this check belongs to.
  final String category;

  /// Human-readable description of what is being checked.
  final String description;

  /// Severity level determining score impact.
  final SaiaSeverity severity;

  /// Criteria for PASS outcome.
  final String passCriteria;

  /// Criteria for WARNING outcome.
  final String warningCriteria;

  /// Criteria for FAIL outcome.
  final String failCriteria;

  /// Estimated time to remediate in minutes.
  final int estimatedMinutes;

  const SaiaAuditCheck({
    required this.id,
    required this.category,
    required this.description,
    required this.severity,
    this.passCriteria = '',
    this.warningCriteria = '',
    this.failCriteria = '',
    this.estimatedMinutes = 30,
  });

  /// Whether this check qualifies as a quick win when failed.
  /// Quick wins are Critical/High severity checks fixable in <15 minutes.
  bool get isQuickWinCandidate =>
      (severity == SaiaSeverity.critical || severity == SaiaSeverity.high) &&
      estimatedMinutes < 15;
}

/// Result of evaluating a single audit check.
class SaiaAuditCheckResult {
  /// The check that was evaluated.
  final SaiaAuditCheck check;

  /// Outcome of the evaluation.
  final SaiaCheckOutcome outcome;

  /// Specific finding or observation.
  final String finding;

  /// Recommended action to fix the issue.
  final String recommendation;

  /// Measured value (if applicable, e.g., "QS: 3.2").
  final String? measuredValue;

  const SaiaAuditCheckResult({
    required this.check,
    required this.outcome,
    this.finding = '',
    this.recommendation = '',
    this.measuredValue,
  });

  /// Whether this is a quick win (critical/high + <15min + failed).
  bool get isQuickWin =>
      check.isQuickWinCandidate && outcome == SaiaCheckOutcome.fail;

  /// Weighted score contribution of this check.
  double weightedScore(double categoryWeight) {
    if (outcome.isExcluded) return 0;
    return outcome.pointsFraction * check.severity.weight * categoryWeight;
  }

  /// Maximum possible weighted score for this check.
  double maxWeightedScore(double categoryWeight) {
    if (outcome.isExcluded) return 0;
    return check.severity.weight * categoryWeight;
  }
}
