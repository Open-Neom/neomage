/// Outcome of a single audit check.
enum SaiaCheckOutcome {
  /// Check passed completely.
  pass_(1.0),

  /// Partial compliance, needs attention.
  warning(0.5),

  /// Check failed, action required.
  fail(0.0),

  /// Not applicable to this context — excluded from scoring.
  notApplicable(-1.0);

  /// Points fraction awarded for this outcome.
  final double pointsFraction;

  const SaiaCheckOutcome(this.pointsFraction);

  bool get isExcluded => this == notApplicable;
}
