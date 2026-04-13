/// A weighted category grouping audit checks.
///
/// Categories allow different domains of evaluation to
/// contribute proportionally to the overall health score.
class SaiaAuditCategory {
  /// Category identifier (e.g., 'conversion_tracking', 'security').
  final String id;

  /// Human-readable category name.
  final String name;

  /// Weight as a fraction (0.0 - 1.0). All categories should sum to 1.0.
  final double weight;

  /// Description of what this category evaluates.
  final String description;

  const SaiaAuditCategory({
    required this.id,
    required this.name,
    required this.weight,
    this.description = '',
  });
}
