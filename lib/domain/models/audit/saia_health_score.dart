import 'saia_audit_check.dart';
import 'saia_audit_category.dart';
import 'saia_check_result.dart';
import 'saia_grade.dart';
import 'saia_severity.dart';

/// Computed health score for a single audit domain.
///
/// Uses the weighted severity algorithm:
/// ```
/// score = Σ(outcome × severity_weight × category_weight)
///       / Σ(max_possible × severity_weight × category_weight) × 100
/// ```
class SaiaHealthScore {
  /// The computed score (0-100).
  final double score;

  /// Letter grade derived from the score.
  final SaiaGrade grade;

  /// All check results that contributed to this score.
  final List<SaiaAuditCheckResult> results;

  /// Categories with their weights.
  final List<SaiaAuditCategory> categories;

  /// Domain label (e.g., 'Google Ads', 'Agent Security', 'Code Quality').
  final String domain;

  const SaiaHealthScore({
    required this.score,
    required this.grade,
    required this.results,
    required this.categories,
    required this.domain,
  });

  /// Compute a health score from check results and categories.
  factory SaiaHealthScore.compute({
    required List<SaiaAuditCheckResult> results,
    required List<SaiaAuditCategory> categories,
    required String domain,
  }) {
    final categoryWeights = {
      for (final cat in categories) cat.id: cat.weight,
    };

    double earned = 0;
    double maxPossible = 0;

    for (final result in results) {
      final catWeight = categoryWeights[result.check.category] ?? 0;
      earned += result.weightedScore(catWeight);
      maxPossible += result.maxWeightedScore(catWeight);
    }

    final score = maxPossible > 0 ? (earned / maxPossible) * 100 : 0.0;
    final grade = SaiaGrade.fromScore(score);

    return SaiaHealthScore(
      score: score,
      grade: grade,
      results: results,
      categories: categories,
      domain: domain,
    );
  }

  // --- Derived metrics ---

  int get totalChecks => results.where((r) => !r.outcome.isExcluded).length;
  int get passedChecks =>
      results.where((r) => r.outcome == SaiaCheckOutcome.pass_).length;
  int get warningChecks =>
      results.where((r) => r.outcome == SaiaCheckOutcome.warning).length;
  int get failedChecks =>
      results.where((r) => r.outcome == SaiaCheckOutcome.fail).length;
  int get naChecks =>
      results.where((r) => r.outcome == SaiaCheckOutcome.notApplicable).length;

  double get passRate => totalChecks > 0 ? passedChecks / totalChecks : 0;

  /// Quick wins: critical/high severity fails fixable in <15 minutes.
  List<SaiaAuditCheckResult> get quickWins =>
      results.where((r) => r.isQuickWin).toList()
        ..sort((a, b) => b.check.severity.weight.compareTo(a.check.severity.weight));

  /// Critical failures that need immediate attention.
  List<SaiaAuditCheckResult> get criticalFailures => results
      .where(
          (r) => r.outcome == SaiaCheckOutcome.fail && r.check.severity == SaiaSeverity.critical)
      .toList();

  /// Per-category breakdown.
  Map<String, double> get categoryScores {
    final catEarned = <String, double>{};
    final catMax = <String, double>{};
    final categoryWeights = {
      for (final cat in categories) cat.id: cat.weight,
    };

    for (final result in results) {
      final catId = result.check.category;
      final catWeight = categoryWeights[catId] ?? 0;
      catEarned[catId] = (catEarned[catId] ?? 0) + result.weightedScore(catWeight);
      catMax[catId] = (catMax[catId] ?? 0) + result.maxWeightedScore(catWeight);
    }

    return {
      for (final catId in catMax.keys)
        catId: catMax[catId]! > 0 ? (catEarned[catId]! / catMax[catId]!) * 100 : 0,
    };
  }

  @override
  String toString() =>
      'SaiaHealthScore($domain: ${score.toStringAsFixed(1)} ${grade.name.toUpperCase()}, '
      '$passedChecks/$totalChecks passed, ${quickWins.length} quick wins)';
}

/// Aggregate health score across multiple domains.
///
/// Weighted by each domain's budget share or importance weight.
class SaiaAggregateScore {
  /// Per-domain scores.
  final Map<String, SaiaHealthScore> domainScores;

  /// Weights per domain (should sum to 1.0).
  final Map<String, double> domainWeights;

  const SaiaAggregateScore({
    required this.domainScores,
    required this.domainWeights,
  });

  /// Compute weighted aggregate score.
  double get score {
    double weighted = 0;
    double totalWeight = 0;
    for (final entry in domainScores.entries) {
      final w = domainWeights[entry.key] ?? 0;
      weighted += entry.value.score * w;
      totalWeight += w;
    }
    return totalWeight > 0 ? weighted / totalWeight : 0;
  }

  SaiaGrade get grade => SaiaGrade.fromScore(score);

  /// All quick wins across all domains, sorted by severity.
  List<SaiaAuditCheckResult> get allQuickWins {
    final wins = <SaiaAuditCheckResult>[];
    for (final hs in domainScores.values) {
      wins.addAll(hs.quickWins);
    }
    wins.sort((a, b) => b.check.severity.weight.compareTo(a.check.severity.weight));
    return wins;
  }
}
