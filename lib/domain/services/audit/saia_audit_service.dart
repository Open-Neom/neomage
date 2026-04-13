import '../../models/audit/saia_audit_category.dart';
import '../../models/audit/saia_audit_check.dart';
import '../../models/audit/saia_audit_report.dart';
import '../../models/audit/saia_health_score.dart';

/// Service contract for running audits against any domain.
///
/// Implementations define the checks, categories, and evaluation logic.
/// The scoring algorithm is domain-agnostic — the same weighted severity
/// formula works for ad accounts, agent security, code quality, etc.
abstract class SaiaAuditService {
  /// Domain identifier for this audit service.
  String get domain;

  /// Define the audit categories and their weights.
  List<SaiaAuditCategory> get categories;

  /// Define all checks for this audit domain.
  List<SaiaAuditCheck> get checks;

  /// Evaluate a single check against the provided data.
  Future<SaiaAuditCheckResult> evaluateCheck(
    SaiaAuditCheck check,
    Map<String, dynamic> data,
  );

  /// Run the full audit and produce a report.
  Future<SaiaAuditReport> audit(Map<String, dynamic> data) async {
    final stopwatch = Stopwatch()..start();
    final results = <SaiaAuditCheckResult>[];

    for (final check in checks) {
      final result = await evaluateCheck(check, data);
      results.add(result);
    }

    stopwatch.stop();

    final healthScore = SaiaHealthScore.compute(
      results: results,
      categories: categories,
      domain: domain,
    );

    return SaiaAuditReport(
      healthScore: healthScore,
      title: '$domain Audit',
      auditedAt: DateTime.now(),
      context: data,
      duration: stopwatch.elapsed,
    );
  }
}
