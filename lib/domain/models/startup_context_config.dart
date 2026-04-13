/// Configuration for startup context injection.
///
/// Controls how memory and context are loaded at the beginning
/// of a new or reset agent session.
class StartupContextConfig {
  /// Whether startup context injection is enabled.
  final bool enabled;

  /// Which session actions trigger startup context injection.
  /// Typically: ['new', 'reset'].
  final List<String> applyOn;

  /// How many days of daily memory files to load.
  final int dailyMemoryDays;

  /// Maximum bytes per memory file before truncation.
  final int maxFileBytes;

  /// Maximum characters per memory file after decoding.
  final int maxFileChars;

  /// Maximum total characters across all memory sources.
  final int maxTotalChars;

  /// Whether to mark injected memory as untrusted.
  final bool markUntrusted;

  const StartupContextConfig({
    this.enabled = true,
    this.applyOn = const ['new', 'reset'],
    this.dailyMemoryDays = 2,
    this.maxFileBytes = 16384,
    this.maxFileChars = 2000,
    this.maxTotalChars = 4500,
    this.markUntrusted = true,
  });

  static const caps = (
    maxDays: 14,
    maxFileBytes: 65536,
    maxFileChars: 10000,
    maxTotalChars: 50000,
  );

  StartupContextConfig copyWith({
    bool? enabled,
    List<String>? applyOn,
    int? dailyMemoryDays,
    int? maxFileBytes,
    int? maxFileChars,
    int? maxTotalChars,
    bool? markUntrusted,
  }) {
    return StartupContextConfig(
      enabled: enabled ?? this.enabled,
      applyOn: applyOn ?? this.applyOn,
      dailyMemoryDays: (dailyMemoryDays ?? this.dailyMemoryDays)
          .clamp(0, caps.maxDays),
      maxFileBytes: (maxFileBytes ?? this.maxFileBytes)
          .clamp(0, caps.maxFileBytes),
      maxFileChars: (maxFileChars ?? this.maxFileChars)
          .clamp(0, caps.maxFileChars),
      maxTotalChars: (maxTotalChars ?? this.maxTotalChars)
          .clamp(0, caps.maxTotalChars),
      markUntrusted: markUntrusted ?? this.markUntrusted,
    );
  }
}
