import 'startup_context_entry.dart';

/// Result of startup context assembly.
class StartupContextResult {
  /// Assembled context prelude ready for injection.
  final String prelude;

  /// Individual entries that compose the prelude.
  final List<StartupContextEntry> entries;

  /// Total characters in the assembled prelude.
  final int totalChars;

  /// Whether any entries were truncated.
  final bool anyTruncated;

  /// Session action that triggered this context load.
  final String triggerAction;

  const StartupContextResult({
    required this.prelude,
    required this.entries,
    required this.totalChars,
    required this.anyTruncated,
    required this.triggerAction,
  });

  bool get isEmpty => entries.isEmpty;
}
