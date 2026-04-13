/// Letter grade derived from a health score.
enum SaiaGrade {
  /// 90-100: Excellent — minor optimizations only.
  a(90, 'Excellent', 'Minor optimizations only'),

  /// 75-89: Good — some improvement opportunities.
  b(75, 'Good', 'Some improvement opportunities'),

  /// 60-74: Needs improvement — notable issues need attention.
  c(60, 'Needs Improvement', 'Notable issues need attention'),

  /// 40-59: Poor — significant problems present.
  d(40, 'Poor', 'Significant problems present'),

  /// 0-39: Critical — urgent intervention required.
  f(0, 'Critical', 'Urgent intervention required');

  /// Minimum score threshold for this grade.
  final int minScore;

  /// Short label for the grade.
  final String label;

  /// Action-oriented description.
  final String actionDescription;

  const SaiaGrade(this.minScore, this.label, this.actionDescription);

  /// Determine grade from a numeric score (0-100).
  static SaiaGrade fromScore(double score) {
    if (score >= 90) return SaiaGrade.a;
    if (score >= 75) return SaiaGrade.b;
    if (score >= 60) return SaiaGrade.c;
    if (score >= 40) return SaiaGrade.d;
    return SaiaGrade.f;
  }
}
