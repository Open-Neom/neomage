// Typed wrappers for session and agent IDs.
// Dart doesn't have branded types, so we use extension types for zero-cost wrapping.

/// Zero-cost typed wrapper for session identifiers.
extension type const SessionId(String value) implements String {
  /// Cast a raw string to SessionId.
  factory SessionId.from(String id) => SessionId(id);
}

/// Zero-cost typed wrapper for agent identifiers.
extension type const AgentId(String value) implements String {
  /// Cast a raw string to AgentId.
  factory AgentId.from(String id) => AgentId(id);

  /// Validate and brand a string as AgentId.
  /// Matches format: `a` + optional `<label>-` + 16 hex chars.
  /// Returns null if the string doesn't match.
  static AgentId? tryParse(String s) {
    final pattern = RegExp(r'^a(?:.+-)?[0-9a-f]{16}$');
    return pattern.hasMatch(s) ? AgentId(s) : null;
  }
}
