import 'saia_audit_check.dart';
import 'saia_check_result.dart';
import 'saia_grade.dart';
import 'saia_health_score.dart';
import 'saia_severity.dart';

/// Complete audit report with findings, action plan, and quick wins.
class SaiaAuditReport {
  /// Health score for this audit.
  final SaiaHealthScore healthScore;

  /// Report title (e.g., 'Google Ads Audit', 'Agent Security Audit').
  final String title;

  /// When the audit was performed.
  final DateTime auditedAt;

  /// Domain-specific context (e.g., business type, agent name).
  final Map<String, dynamic> context;

  /// Duration of the audit execution.
  final Duration duration;

  const SaiaAuditReport({
    required this.healthScore,
    required this.title,
    required this.auditedAt,
    this.context = const {},
    this.duration = Duration.zero,
  });

  double get score => healthScore.score;
  SaiaGrade get grade => healthScore.grade;

  /// Generate a prioritized action plan from audit results.
  List<SaiaActionItem> get actionPlan {
    final items = <SaiaActionItem>[];

    for (final result in healthScore.results) {
      if (result.outcome == SaiaCheckOutcome.pass_ ||
          result.outcome == SaiaCheckOutcome.notApplicable) {
        continue;
      }

      items.add(SaiaActionItem(
        checkId: result.check.id,
        category: result.check.category,
        severity: result.check.severity,
        description: result.check.description,
        finding: result.finding,
        recommendation: result.recommendation,
        estimatedMinutes: result.check.estimatedMinutes,
        isQuickWin: result.isQuickWin,
        priority: _computePriority(result),
      ));
    }

    items.sort((a, b) => b.priority.compareTo(a.priority));
    return items;
  }

  /// Quick wins: high-impact fixes under 15 minutes.
  List<SaiaActionItem> get quickWins =>
      actionPlan.where((a) => a.isQuickWin).toList();

  /// Format as markdown report.
  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# $title');
    buf.writeln();
    buf.writeln('**Score:** ${score.toStringAsFixed(1)}/100 '
        '(${grade.name.toUpperCase()}: ${grade.label})');
    buf.writeln('**Audited:** ${auditedAt.toIso8601String().substring(0, 10)}');
    buf.writeln('**Duration:** ${duration.inSeconds}s');
    buf.writeln('**Checks:** ${healthScore.totalChecks} total, '
        '${healthScore.passedChecks} passed, '
        '${healthScore.warningChecks} warnings, '
        '${healthScore.failedChecks} failed');
    buf.writeln();

    // Category breakdown
    buf.writeln('## Category Breakdown');
    buf.writeln();
    buf.writeln('| Category | Score |');
    buf.writeln('|----------|-------|');
    for (final entry in healthScore.categoryScores.entries) {
      buf.writeln('| ${entry.key} | ${entry.value.toStringAsFixed(1)} |');
    }
    buf.writeln();

    // Quick wins
    if (quickWins.isNotEmpty) {
      buf.writeln('## Quick Wins');
      buf.writeln();
      for (final qw in quickWins) {
        buf.writeln('- **[${qw.checkId}]** ${qw.description} '
            '(~${qw.estimatedMinutes} min)');
        if (qw.recommendation.isNotEmpty) {
          buf.writeln('  → ${qw.recommendation}');
        }
      }
      buf.writeln();
    }

    // Full action plan
    buf.writeln('## Action Plan');
    buf.writeln();
    buf.writeln('| Priority | ID | Category | Finding | Action | Time |');
    buf.writeln('|----------|----|---------|---------|----|------|');
    for (final item in actionPlan) {
      buf.writeln('| ${item.severity.name} | ${item.checkId} | '
          '${item.category} | ${item.finding} | '
          '${item.recommendation} | ${item.estimatedMinutes}m |');
    }

    return buf.toString();
  }

  static double _computePriority(SaiaAuditCheckResult result) {
    double base = result.check.severity.weight;
    if (result.outcome == SaiaCheckOutcome.fail) base *= 2;
    if (result.isQuickWin) base *= 1.5;
    return base;
  }
}

/// A single prioritized action item from an audit.
class SaiaActionItem {
  final String checkId;
  final String category;
  final SaiaSeverity severity;
  final String description;
  final String finding;
  final String recommendation;
  final int estimatedMinutes;
  final bool isQuickWin;
  final double priority;

  const SaiaActionItem({
    required this.checkId,
    required this.category,
    required this.severity,
    required this.description,
    required this.finding,
    required this.recommendation,
    required this.estimatedMinutes,
    required this.isQuickWin,
    required this.priority,
  });
}
