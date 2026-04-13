import '../../models/audit/saia_health_score.dart';
import 'saia_audit_service.dart';

/// Orchestrates multiple audit services in parallel.
///
/// Mirrors the claude-ads pattern of spawning 6+ audit agents
/// concurrently, then aggregating results into a unified score.
class SaiaParallelAuditService {
  final List<SaiaAuditService> _services;

  SaiaParallelAuditService(this._services);

  /// Run all audit services in parallel and aggregate results.
  ///
  /// [domainWeights] maps each domain to its importance weight
  /// (e.g., budget share). If not provided, equal weight is used.
  Future<SaiaAggregateScore> auditAll(
    Map<String, dynamic> data, {
    Map<String, double>? domainWeights,
  }) async {
    final futures = _services.map((s) => s.audit(data));
    final reports = await Future.wait(futures);

    final scores = <String, SaiaHealthScore>{};
    for (final report in reports) {
      scores[report.healthScore.domain] = report.healthScore;
    }

    final weights = domainWeights ??
        {for (final s in _services) s.domain: 1.0 / _services.length};

    return SaiaAggregateScore(
      domainScores: scores,
      domainWeights: weights,
    );
  }
}
