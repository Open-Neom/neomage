// Effort manager — port of neomage/src/utils/effort.ts, thinking.ts,
// tokenBudget.ts, words.ts.
// Effort level management, thinking configuration, token budget parsing,
// and random word slug generation.

import 'dart:math';

// ============================================================================
// Part 1: Effort levels (from effort.ts)
// ============================================================================

/// Effort levels for the API.
enum EffortLevel {
  low,
  medium,
  high,
  max;

  /// Parse from a string, returning null if invalid.
  static EffortLevel? tryParse(String value) {
    final lower = value.toLowerCase();
    for (final level in values) {
      if (level.name == lower) return level;
    }
    return null;
  }
}

/// All valid effort levels.
const List<EffortLevel> kEffortLevels = EffortLevel.values;

/// Effort value can be either a named level or a numeric value.
sealed class EffortValue {
  const EffortValue();

  /// Create from a named level.
  const factory EffortValue.level(EffortLevel level) = EffortLevelValue;

  /// Create from a numeric value.
  const factory EffortValue.numeric(int value) = EffortNumericValue;

  /// Get the effort level this value represents.
  EffortLevel toLevel({bool isAnt = false});
}

/// A named effort level value.
class EffortLevelValue extends EffortValue {
  final EffortLevel level;
  const EffortLevelValue(this.level);

  @override
  EffortLevel toLevel({bool isAnt = false}) => level;

  @override
  bool operator ==(Object other) =>
      other is EffortLevelValue && other.level == level;

  @override
  int get hashCode => level.hashCode;

  @override
  String toString() => 'EffortLevelValue(${level.name})';
}

/// A numeric effort value (ant-only feature).
class EffortNumericValue extends EffortValue {
  final int value;
  const EffortNumericValue(this.value);

  @override
  EffortLevel toLevel({bool isAnt = false}) {
    if (isAnt) {
      if (value <= 50) return EffortLevel.low;
      if (value <= 85) return EffortLevel.medium;
      if (value <= 100) return EffortLevel.high;
      return EffortLevel.max;
    }
    return EffortLevel.high;
  }

  @override
  bool operator ==(Object other) =>
      other is EffortNumericValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'EffortNumericValue($value)';
}

/// Configuration callbacks for effort management.
class EffortConfig {
  /// Get the API provider.
  final String Function() getApiProvider;

  /// Check if an env var is truthy.
  final bool Function(String name) isEnvTruthy;

  /// Get the user type (e.g., 'ant').
  final String? Function() getUserType;

  /// Get 3P model capability override.
  final bool? Function(String model, String capability)
  get3PModelCapabilityOverride;

  /// Get the canonical name for a model.
  final String Function(String model) getCanonicalName;

  /// Get initial settings.
  final Map<String, dynamic> Function() getInitialSettings;

  /// Get settings for a specific source.
  final Map<String, dynamic>? Function(String source) getSettingsForSource;

  /// Get settings with errors.
  final ({Map<String, dynamic> settings, List<String> errors}) Function()
  getSettingsWithErrors;

  /// Get a cached feature value from remote config.
  final T Function<T>(String key, T defaultValue) getFeatureValue;

  /// Check if the user is a Pro subscriber.
  final bool Function() isProSubscriber;

  /// Check if the user is a Max subscriber.
  final bool Function() isMaxSubscriber;

  /// Check if the user is a Team subscriber.
  final bool Function() isTeamSubscriber;

  /// Check if ultrathink is enabled.
  final bool Function() isUltrathinkEnabled;

  /// Resolve ant-internal model overrides. Returns null if not an ant model.
  final Map<String, dynamic>? Function(String model) resolveAntModel;

  /// Get ant model override config.
  final Map<String, dynamic>? Function() getAntModelOverrideConfig;

  const EffortConfig({
    required this.getApiProvider,
    required this.isEnvTruthy,
    required this.getUserType,
    required this.get3PModelCapabilityOverride,
    required this.getCanonicalName,
    required this.getInitialSettings,
    required this.getSettingsForSource,
    required this.getSettingsWithErrors,
    required this.getFeatureValue,
    required this.isProSubscriber,
    required this.isMaxSubscriber,
    required this.isTeamSubscriber,
    required this.isUltrathinkEnabled,
    required this.resolveAntModel,
    required this.getAntModelOverrideConfig,
  });
}

/// Manages effort levels, model support, and defaults.
class EffortManager {
  final EffortConfig _config;

  const EffortManager(this._config);

  bool get _isAnt => _config.getUserType() == 'ant';

  /// Check if a model supports the effort parameter.
  bool modelSupportsEffort(String model) {
    final m = model.toLowerCase();
    if (_config.isEnvTruthy('MAGE_ALWAYS_ENABLE_EFFORT')) {
      return true;
    }
    final supported3P = _config.get3PModelCapabilityOverride(model, 'effort');
    if (supported3P != null) return supported3P;

    // Supported by a subset of Neomage 4 models.
    if (m.contains('opus-4-6') || m.contains('sonnet-4-6')) return true;

    // Exclude any other known legacy models.
    if (m.contains('haiku') || m.contains('sonnet') || m.contains('opus')) {
      return false;
    }

    // Default to true for unknown model strings on 1P.
    return _config.getApiProvider() == 'firstParty';
  }

  /// Check if a model supports 'max' effort (Opus 4.6 only for public models).
  bool modelSupportsMaxEffort(String model) {
    final supported3P = _config.get3PModelCapabilityOverride(
      model,
      'max_effort',
    );
    if (supported3P != null) return supported3P;
    if (model.toLowerCase().contains('opus-4-6')) return true;
    if (_isAnt) {
      final antModel = _config.resolveAntModel(model);
      if (antModel != null) return true;
    }
    return false;
  }

  /// Check if a value is a valid effort level string.
  bool isEffortLevel(String value) {
    return EffortLevel.tryParse(value) != null;
  }

  /// Parse an effort value from an unknown input.
  EffortValue? parseEffortValue(Object? value) {
    if (value == null || (value is String && value.isEmpty)) return null;

    if (value is int && _isValidNumericEffort(value)) {
      return EffortNumericValue(value);
    }

    final str = value.toString().toLowerCase();
    final level = EffortLevel.tryParse(str);
    if (level != null) return EffortLevelValue(level);

    final numericValue = int.tryParse(str);
    if (numericValue != null && _isValidNumericEffort(numericValue)) {
      return EffortNumericValue(numericValue);
    }

    return null;
  }

  /// Numeric values are model-default only and not persisted. 'max' is
  /// session-scoped for external users (ants can persist it).
  EffortLevel? toPersistableEffort(EffortValue? value) {
    if (value is EffortLevelValue) {
      if (value.level == EffortLevel.low ||
          value.level == EffortLevel.medium ||
          value.level == EffortLevel.high) {
        return value.level;
      }
      if (value.level == EffortLevel.max && _isAnt) {
        return value.level;
      }
    }
    return null;
  }

  /// Get the initial effort setting from settings.
  EffortLevel? getInitialEffortSetting() {
    final settings = _config.getInitialSettings();
    final level = settings['effortLevel'] as String?;
    if (level == null) return null;
    final parsed = EffortLevel.tryParse(level);
    return toPersistableEffort(
      parsed != null ? EffortLevelValue(parsed) : null,
    );
  }

  /// Decide what effort level to persist when the user selects a model
  /// in ModelPicker.
  EffortLevel? resolvePickerEffortPersistence({
    required EffortLevel? picked,
    required EffortLevel modelDefault,
    required EffortLevel? priorPersisted,
    required bool toggledInPicker,
  }) {
    final hadExplicit = priorPersisted != null || toggledInPicker;
    return hadExplicit || picked != modelDefault ? picked : null;
  }

  /// Get the effort value from the environment variable override.
  /// Returns null for 'unset'/'auto', or the parsed value.
  /// Returns a special sentinel for "env not set".
  EffortValue? getEffortEnvOverride() {
    final envOverride = const String.fromEnvironment(
      'MAGE_EFFORT_LEVEL',
      defaultValue: '',
    );
    if (envOverride.isEmpty) return null;
    final lower = envOverride.toLowerCase();
    if (lower == 'unset' || lower == 'auto') {
      return null; // Caller distinguishes via separate check.
    }
    return parseEffortValue(envOverride);
  }

  /// Check if the env override is explicitly set to 'unset' or 'auto'.
  bool get isEffortEnvUnset {
    final envOverride = const String.fromEnvironment(
      'MAGE_EFFORT_LEVEL',
      defaultValue: '',
    );
    if (envOverride.isEmpty) return false;
    final lower = envOverride.toLowerCase();
    return lower == 'unset' || lower == 'auto';
  }

  /// Resolve the effort value that will actually be sent to the API.
  /// Follows the full precedence chain:
  ///   env MAGE_EFFORT_LEVEL -> appState.effortValue -> model default
  EffortValue? resolveAppliedEffort(
    String model,
    EffortValue? appStateEffortValue,
  ) {
    if (isEffortEnvUnset) return null;
    final envOverride = getEffortEnvOverride();
    final resolved =
        envOverride ?? appStateEffortValue ?? getDefaultEffortForModel(model);
    // API rejects 'max' on non-Opus-4.6 models -- downgrade to 'high'.
    if (resolved is EffortLevelValue &&
        resolved.level == EffortLevel.max &&
        !modelSupportsMaxEffort(model)) {
      return const EffortLevelValue(EffortLevel.high);
    }
    return resolved;
  }

  /// Resolve the effort level to show the user.
  EffortLevel getDisplayedEffortLevel(
    String model,
    EffortValue? appStateEffort,
  ) {
    final resolved = resolveAppliedEffort(model, appStateEffort);
    return resolved?.toLevel(isAnt: _isAnt) ?? EffortLevel.high;
  }

  /// Build the ` with {level} effort` suffix shown in Logo/Spinner.
  String getEffortSuffix(String model, EffortValue? effortValue) {
    if (effortValue == null) return '';
    final resolved = resolveAppliedEffort(model, effortValue);
    if (resolved == null) return '';
    return ' with ${resolved.toLevel(isAnt: _isAnt).name} effort';
  }

  /// Check if a numeric effort value is valid.
  bool _isValidNumericEffort(int value) => true; // Integer is valid

  /// Convert an effort value to its named level.
  EffortLevel convertEffortValueToLevel(EffortValue value) {
    return value.toLevel(isAnt: _isAnt);
  }

  /// Get user-facing description for effort levels.
  String getEffortLevelDescription(EffortLevel level) {
    switch (level) {
      case EffortLevel.low:
        return 'Quick, straightforward implementation with minimal overhead';
      case EffortLevel.medium:
        return 'Balanced approach with standard implementation and testing';
      case EffortLevel.high:
        return 'Comprehensive implementation with extensive testing and documentation';
      case EffortLevel.max:
        return 'Maximum capability with deepest reasoning (Opus 4.6 only)';
    }
  }

  /// Get user-facing description for effort values.
  String getEffortValueDescription(EffortValue value) {
    if (_isAnt && value is EffortNumericValue) {
      return '[ANT-ONLY] Numeric effort value of ${value.value}';
    }
    if (value is EffortLevelValue) {
      return getEffortLevelDescription(value.level);
    }
    return 'Balanced approach with standard implementation and testing';
  }

  /// Opus default effort configuration.
  OpusDefaultEffortConfig getOpusDefaultEffortConfig() {
    final config = _config.getFeatureValue<Map<String, dynamic>?>(
      'tengu_grey_step2',
      null,
    );
    return OpusDefaultEffortConfig(
      enabled: config?['enabled'] as bool? ?? true,
      dialogTitle:
          config?['dialogTitle'] as String? ??
          'We recommend medium effort for Opus',
      dialogDescription:
          config?['dialogDescription'] as String? ??
          'Effort determines how long Neomage thinks for when completing '
              'your task. We recommend medium effort for most tasks to '
              'balance speed and intelligence and maximize rate limits. '
              'Use ultrathink to trigger high effort when needed.',
    );
  }

  /// Get the default effort for a model.
  EffortValue? getDefaultEffortForModel(String model) {
    if (_isAnt) {
      final overrideConfig = _config.getAntModelOverrideConfig();
      if (overrideConfig != null) {
        final defaultModel = overrideConfig['defaultModel'] as String?;
        final isDefaultModel =
            defaultModel != null &&
            model.toLowerCase() == defaultModel.toLowerCase();
        if (isDefaultModel) {
          final level = overrideConfig['defaultModelEffortLevel'] as String?;
          if (level != null) {
            final parsed = EffortLevel.tryParse(level);
            if (parsed != null) return EffortLevelValue(parsed);
          }
        }
      }
      final antModel = _config.resolveAntModel(model);
      if (antModel != null) {
        final level = antModel['defaultEffortLevel'] as String?;
        if (level != null) {
          final parsed = EffortLevel.tryParse(level);
          if (parsed != null) return EffortLevelValue(parsed);
        }
        final numValue = antModel['defaultEffortValue'] as int?;
        if (numValue != null) return EffortNumericValue(numValue);
      }
      // Always default ants to undefined/high.
      return null;
    }

    // Default effort on Opus 4.6 to medium for Pro.
    // Max/Team also get medium when the tengu_grey_step2 config is enabled.
    if (model.toLowerCase().contains('opus-4-6')) {
      if (_config.isProSubscriber()) {
        return const EffortLevelValue(EffortLevel.medium);
      }
      if (getOpusDefaultEffortConfig().enabled &&
          (_config.isMaxSubscriber() || _config.isTeamSubscriber())) {
        return const EffortLevelValue(EffortLevel.medium);
      }
    }

    // When ultrathink is enabled, default to medium.
    if (_config.isUltrathinkEnabled() && modelSupportsEffort(model)) {
      return const EffortLevelValue(EffortLevel.medium);
    }

    // Fallback to undefined = high effort in the API.
    return null;
  }
}

/// Configuration for Opus default effort display.
class OpusDefaultEffortConfig {
  final bool enabled;
  final String dialogTitle;
  final String dialogDescription;

  const OpusDefaultEffortConfig({
    required this.enabled,
    required this.dialogTitle,
    required this.dialogDescription,
  });
}

// ============================================================================
// Part 2: Thinking configuration (from thinking.ts)
// ============================================================================

/// Thinking/extended thinking configuration for the API.
sealed class ThinkingConfig {
  const ThinkingConfig();
}

/// Adaptive thinking -- let the model decide.
class ThinkingAdaptive extends ThinkingConfig {
  const ThinkingAdaptive();
}

/// Thinking enabled with a specific token budget.
class ThinkingEnabled extends ThinkingConfig {
  final int budgetTokens;
  const ThinkingEnabled({required this.budgetTokens});
}

/// Thinking explicitly disabled.
class ThinkingDisabled extends ThinkingConfig {
  const ThinkingDisabled();
}

/// Rainbow theme color keys.
const List<String> kRainbowColors = [
  'rainbow_red',
  'rainbow_orange',
  'rainbow_yellow',
  'rainbow_green',
  'rainbow_blue',
  'rainbow_indigo',
  'rainbow_violet',
];

/// Rainbow shimmer color keys.
const List<String> kRainbowShimmerColors = [
  'rainbow_red_shimmer',
  'rainbow_orange_shimmer',
  'rainbow_yellow_shimmer',
  'rainbow_green_shimmer',
  'rainbow_blue_shimmer',
  'rainbow_indigo_shimmer',
  'rainbow_violet_shimmer',
];

/// Get the rainbow color key for a given character index.
String getRainbowColor(int charIndex, {bool shimmer = false}) {
  final colors = shimmer ? kRainbowShimmerColors : kRainbowColors;
  return colors[charIndex % colors.length];
}

/// Thinking support manager. Separate from effort to avoid circular deps.
class ThinkingManager {
  final EffortConfig _config;

  const ThinkingManager(this._config);

  /// Build-time gate + runtime gate for ultrathink.
  bool isUltrathinkEnabled() {
    return _config.isUltrathinkEnabled();
  }

  /// Check if text contains the "ultrathink" keyword.
  bool hasUltrathinkKeyword(String text) {
    return RegExp(r'\bultrathink\b', caseSensitive: false).hasMatch(text);
  }

  /// Find positions of "ultrathink" keyword in text (for UI highlighting).
  List<({String word, int start, int end})> findThinkingTriggerPositions(
    String text,
  ) {
    final positions = <({String word, int start, int end})>[];
    final matches = RegExp(
      r'\bultrathink\b',
      caseSensitive: false,
    ).allMatches(text);
    for (final match in matches) {
      positions.add((
        word: match.group(0)!,
        start: match.start,
        end: match.end,
      ));
    }
    return positions;
  }

  /// Check if a model supports extended thinking.
  bool modelSupportsThinking(String model) {
    final supported3P = _config.get3PModelCapabilityOverride(model, 'thinking');
    if (supported3P != null) return supported3P;

    if (_config.getUserType() == 'ant') {
      final antModel = _config.resolveAntModel(model.toLowerCase());
      if (antModel != null) return true;
    }

    final canonical = _config.getCanonicalName(model);
    final provider = _config.getApiProvider();

    // 1P and Foundry: all Neomage 4+ models.
    if (provider == 'foundry' || provider == 'firstParty') {
      return !canonical.contains('claude-3-');
    }
    // 3P (Bedrock/Vertex): only Opus 4+ and Sonnet 4+.
    return canonical.contains('sonnet-4') || canonical.contains('opus-4');
  }

  /// Check if a model supports adaptive thinking.
  bool modelSupportsAdaptiveThinking(String model) {
    final supported3P = _config.get3PModelCapabilityOverride(
      model,
      'adaptive_thinking',
    );
    if (supported3P != null) return supported3P;

    final canonical = _config.getCanonicalName(model);
    if (canonical.contains('opus-4-6') || canonical.contains('sonnet-4-6')) {
      return true;
    }
    if (canonical.contains('opus') ||
        canonical.contains('sonnet') ||
        canonical.contains('haiku')) {
      return false;
    }

    final provider = _config.getApiProvider();
    return provider == 'firstParty' || provider == 'foundry';
  }

  /// Check if thinking should be enabled by default.
  bool shouldEnableThinkingByDefault() {
    final maxThinkingTokensEnv = const String.fromEnvironment(
      'MAX_THINKING_TOKENS',
      defaultValue: '',
    );
    if (maxThinkingTokensEnv.isNotEmpty) {
      final val = int.tryParse(maxThinkingTokensEnv);
      return val != null && val > 0;
    }

    final settingsResult = _config.getSettingsWithErrors();
    if (settingsResult.settings['alwaysThinkingEnabled'] == false) {
      return false;
    }

    return true;
  }
}

// ============================================================================
// Part 3: Token budget parsing (from tokenBudget.ts)
// ============================================================================

/// Shorthand regex (+500k) anchored to start.
final RegExp _shorthandStartRe = RegExp(
  r'^\s*\+(\d+(?:\.\d+)?)\s*(k|m|b)\b',
  caseSensitive: false,
);

/// Shorthand regex (+500k) anchored to end.
final RegExp _shorthandEndRe = RegExp(
  r'\s\+(\d+(?:\.\d+)?)\s*(k|m|b)\s*[.!?]?\s*$',
  caseSensitive: false,
);

/// Verbose regex (use/spend 2M tokens) matches anywhere.
final RegExp _verboseRe = RegExp(
  r'\b(?:use|spend)\s+(\d+(?:\.\d+)?)\s*(k|m|b)\s*tokens?\b',
  caseSensitive: false,
);

/// Verbose regex with global flag for finding all positions.
final RegExp _verboseReG = RegExp(
  r'\b(?:use|spend)\s+(\d+(?:\.\d+)?)\s*(k|m|b)\s*tokens?\b',
  caseSensitive: false,
);

const Map<String, int> _multipliers = {
  'k': 1000,
  'm': 1000000,
  'b': 1000000000,
};

double _parseBudgetMatch(String value, String suffix) {
  return double.parse(value) * _multipliers[suffix.toLowerCase()]!;
}

/// Parse a token budget from text. Returns null if no budget is found.
///
/// Supports:
///   - Shorthand at start: `+500k fix the bug`
///   - Shorthand at end: `fix the bug +500k`
///   - Verbose anywhere: `use 2M tokens to fix the bug`
int? parseTokenBudget(String text) {
  final startMatch = _shorthandStartRe.firstMatch(text);
  if (startMatch != null) {
    return _parseBudgetMatch(
      startMatch.group(1)!,
      startMatch.group(2)!,
    ).round();
  }
  final endMatch = _shorthandEndRe.firstMatch(text);
  if (endMatch != null) {
    return _parseBudgetMatch(endMatch.group(1)!, endMatch.group(2)!).round();
  }
  final verboseMatch = _verboseRe.firstMatch(text);
  if (verboseMatch != null) {
    return _parseBudgetMatch(
      verboseMatch.group(1)!,
      verboseMatch.group(2)!,
    ).round();
  }
  return null;
}

/// Find all token budget positions in text (for UI highlighting).
List<({int start, int end})> findTokenBudgetPositions(String text) {
  final positions = <({int start, int end})>[];

  final startMatch = _shorthandStartRe.firstMatch(text);
  if (startMatch != null) {
    final offset =
        startMatch.start +
        startMatch.group(0)!.length -
        startMatch.group(0)!.trimLeft().length;
    positions.add((
      start: offset,
      end: startMatch.start + startMatch.group(0)!.length,
    ));
  }

  final endMatch = _shorthandEndRe.firstMatch(text);
  if (endMatch != null) {
    final endStart = endMatch.start + 1; // +1: regex includes leading \s
    // Avoid double-counting when input is just "+500k".
    final alreadyCovered = positions.any(
      (p) => endStart >= p.start && endStart < p.end,
    );
    if (!alreadyCovered) {
      positions.add((
        start: endStart,
        end: endMatch.start + endMatch.group(0)!.length,
      ));
    }
  }

  for (final match in _verboseReG.allMatches(text)) {
    positions.add((start: match.start, end: match.end));
  }

  return positions;
}

/// Build the continuation message for a token budget.
String getBudgetContinuationMessage(int pct, int turnTokens, int budget) {
  String fmt(int n) {
    // Format number with commas.
    final str = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  return 'Stopped at $pct% of token target (${fmt(turnTokens)} / ${fmt(budget)}). '
      'Keep working \u2014 do not summarize.';
}

// ============================================================================
// Part 4: Word slug generation (from words.ts)
// ============================================================================

/// Adjectives for slug generation -- whimsical and delightful.
const List<String> kAdjectives = [
  // Classic pleasant adjectives
  'abundant', 'ancient', 'bright', 'calm', 'cheerful', 'clever', 'cozy',
  'curious', 'dapper', 'dazzling', 'deep', 'delightful', 'eager', 'elegant',
  'enchanted', 'fancy', 'fluffy', 'gentle', 'gleaming', 'golden', 'graceful',
  'happy', 'hidden', 'humble', 'jolly', 'joyful', 'keen', 'kind', 'lively',
  'lovely', 'lucky', 'luminous', 'magical', 'majestic', 'mellow', 'merry',
  'mighty', 'misty', 'noble', 'peaceful', 'playful', 'polished', 'precious',
  'proud', 'quiet', 'quirky', 'radiant', 'rosy', 'serene', 'shiny', 'silly',
  'sleepy', 'smooth', 'snazzy', 'snug', 'snuggly', 'soft', 'sparkling',
  'spicy', 'splendid', 'sprightly', 'starry', 'steady', 'sunny', 'swift',
  'tender', 'tidy', 'toasty', 'tranquil', 'twinkly', 'valiant', 'vast',
  'velvet', 'vivid', 'warm', 'whimsical', 'wild', 'wise', 'witty',
  'wondrous', 'zany', 'zesty', 'zippy',
  // Whimsical / magical
  'breezy', 'bubbly', 'buzzing', 'cheeky', 'cosmic', 'crispy',
  'crystalline', 'cuddly', 'drifting', 'dreamy', 'effervescent', 'ethereal',
  'fizzy', 'flickering', 'floating', 'floofy', 'fluttering', 'foamy',
  'frolicking', 'fuzzy', 'giggly', 'glimmering', 'glistening', 'glittery',
  'glowing', 'goofy', 'groovy', 'harmonic', 'hazy', 'humming', 'iridescent',
  'jaunty', 'jazzy', 'jiggly', 'melodic', 'moonlit', 'mossy', 'nifty',
  'peppy', 'prancy', 'purrfect', 'purring', 'quizzical', 'rippling',
  'rustling', 'shimmering', 'shimmying', 'snappy', 'snoopy', 'squishy',
  'swirling', 'ticklish', 'tingly', 'twinkling', 'velvety', 'wiggly',
  'wobbly', 'woolly', 'zazzy',
  // Programming concepts
  'abstract', 'adaptive', 'agile', 'async', 'atomic', 'binary', 'cached',
  'compiled', 'composed', 'compressed', 'concurrent', 'cryptic', 'curried',
  'declarative', 'delegated', 'distributed', 'dynamic', 'encapsulated',
  'enumerated', 'eventual', 'expressive', 'federated', 'functional',
  'generic', 'greedy', 'hashed', 'idempotent', 'immutable', 'imperative',
  'indexed', 'inherited', 'iterative', 'lazy', 'lexical', 'linear', 'linked',
  'logical', 'memoized', 'modular', 'mutable', 'nested', 'optimized',
  'parallel', 'parsed', 'partitioned', 'piped', 'polymorphic', 'pure',
  'reactive', 'recursive', 'refactored', 'reflective', 'replicated',
  'resilient', 'robust', 'scalable', 'sequential', 'serialized', 'sharded',
  'sorted', 'staged', 'stateful', 'stateless', 'streamed', 'structured',
  'synchronous', 'synthetic', 'temporal', 'transient', 'typed', 'unified',
  'validated', 'vectorized', 'virtual',
];

/// Nouns for slug generation -- whimsical creatures, nature, and fun objects.
const List<String> kNouns = [
  // Nature & cosmic
  'aurora', 'avalanche', 'blossom', 'breeze', 'brook', 'bubble', 'canyon',
  'cascade', 'cloud', 'clover', 'comet', 'coral', 'cosmos', 'creek',
  'crescent', 'crystal', 'dawn', 'dewdrop', 'dusk', 'eclipse', 'ember',
  'feather', 'fern', 'firefly', 'flame', 'flurry', 'fog', 'forest', 'frost',
  'galaxy', 'garden', 'glacier', 'glade', 'grove', 'harbor', 'horizon',
  'island', 'lagoon', 'lake', 'leaf', 'lightning', 'meadow', 'meteor',
  'mist', 'moon', 'moonbeam', 'mountain', 'nebula', 'nova', 'ocean',
  'orbit', 'pebble', 'petal', 'pine', 'planet', 'pond', 'puddle', 'quasar',
  'rain', 'rainbow', 'reef', 'ripple', 'river', 'shore', 'sky', 'snowflake',
  'spark', 'spring', 'star', 'stardust', 'starlight', 'storm', 'stream',
  'summit', 'sun', 'sunbeam', 'sunrise', 'sunset', 'thunder', 'tide',
  'twilight', 'valley', 'volcano', 'waterfall', 'wave', 'willow', 'wind',
  // Cute creatures
  'alpaca', 'axolotl', 'badger', 'bear', 'beaver', 'bee', 'bird',
  'bumblebee', 'bunny', 'cat', 'chipmunk', 'crab', 'crane', 'deer',
  'dolphin', 'dove', 'dragon', 'dragonfly', 'duckling', 'eagle', 'elephant',
  'falcon', 'finch', 'flamingo', 'fox', 'frog', 'giraffe', 'goose',
  'hamster', 'hare', 'hedgehog', 'hippo', 'hummingbird', 'jellyfish',
  'kitten', 'koala', 'ladybug', 'lark', 'lemur', 'llama', 'lobster', 'lynx',
  'manatee', 'meerkat', 'moth', 'narwhal', 'newt', 'octopus', 'otter',
  'owl', 'panda', 'parrot', 'peacock', 'pelican', 'penguin', 'phoenix',
  'piglet', 'platypus', 'pony', 'porcupine', 'puffin', 'puppy', 'quail',
  'quokka', 'rabbit', 'raccoon', 'raven', 'robin', 'salamander', 'seahorse',
  'seal', 'sloth', 'snail', 'sparrow', 'sphinx', 'squid', 'squirrel',
  'starfish', 'swan', 'tiger', 'toucan', 'turtle', 'unicorn', 'walrus',
  'whale', 'wolf', 'wombat', 'wren', 'yeti', 'zebra',
  // Fun objects & concepts
  'acorn', 'anchor', 'balloon', 'beacon', 'biscuit', 'blanket', 'bonbon',
  'book', 'boot', 'cake', 'candle', 'candy', 'castle', 'charm', 'clock',
  'cocoa', 'cookie', 'crayon', 'crown', 'cupcake', 'donut', 'dream',
  'fairy', 'fiddle', 'flask', 'flute', 'fountain', 'gadget', 'gem', 'gizmo',
  'globe', 'goblet', 'hammock', 'harp', 'haven', 'hearth', 'honey',
  'journal', 'kazoo', 'kettle', 'key', 'kite', 'lantern', 'lemon',
  'lighthouse', 'locket', 'lollipop', 'mango', 'map', 'marble',
  'marshmallow', 'melody', 'mitten', 'mochi', 'muffin', 'music', 'nest',
  'noodle', 'oasis', 'origami', 'pancake', 'parasol', 'peach', 'pearl',
  'pie', 'pillow', 'pinwheel', 'pixel', 'pizza', 'plum', 'popcorn',
  'pretzel', 'prism', 'pudding', 'pumpkin', 'puzzle', 'quiche', 'quill',
  'quilt', 'riddle', 'rocket', 'rose', 'scone', 'scroll', 'shell', 'sketch',
  'snowglobe', 'sonnet', 'sparkle', 'spindle', 'sprout', 'sundae', 'swing',
  'taco', 'teacup', 'teapot', 'thimble', 'toast', 'token', 'tome', 'tower',
  'treasure', 'treehouse', 'trinket', 'truffle', 'tulip', 'umbrella',
  'waffle', 'wand', 'whisper', 'whistle', 'widget', 'wreath', 'zephyr',
  // Computer scientists
  'abelson', 'adleman', 'aho', 'allen', 'babbage', 'bachman', 'backus',
  'barto', 'bengio', 'bentley', 'blum', 'boole', 'brooks', 'catmull',
  'cerf', 'cherny', 'church', 'clarke', 'cocke', 'codd', 'conway', 'cook',
  'corbato', 'cray', 'curry', 'dahl', 'diffie', 'dijkstra', 'dongarra',
  'eich', 'emerson', 'engelbart', 'feigenbaum', 'floyd', 'gosling', 'graham',
  'gray', 'hamming', 'hanrahan', 'hartmanis', 'hejlsberg', 'hellman',
  'hennessy', 'hickey', 'hinton', 'hoare', 'hollerith', 'hopcroft',
  'hopper', 'iverson', 'kahan', 'kahn', 'karp', 'kay', 'kernighan',
  'knuth', 'kurzweil', 'lamport', 'lampson', 'lecun', 'lerdorf', 'liskov',
  'lovelace', 'matsumoto', 'mccarthy', 'metcalfe', 'micali', 'milner',
  'minsky', 'moler', 'moore', 'naur', 'neumann', 'newell', 'nygaard',
  'papert', 'parnas', 'pascal', 'patterson', 'pearl', 'perlis', 'pike',
  'pnueli', 'rabin', 'reddy', 'ritchie', 'rivest', 'rossum', 'russell',
  'scott', 'sedgewick', 'shamir', 'shannon', 'sifakis', 'simon', 'stallman',
  'stearns', 'steele', 'stonebraker', 'stroustrup', 'sutherland', 'sutton',
  'tarjan', 'thacker', 'thompson', 'torvalds', 'turing', 'ullman', 'valiant',
  'wadler', 'wall', 'wigderson', 'wilkes', 'wilkinson', 'wirth', 'wozniak',
  'yao',
];

/// Verbs for the middle word -- whimsical action words.
const List<String> kVerbs = [
  'baking',
  'beaming',
  'booping',
  'bouncing',
  'brewing',
  'bubbling',
  'chasing',
  'churning',
  'coalescing',
  'conjuring',
  'cooking',
  'crafting',
  'crunching',
  'cuddling',
  'dancing',
  'dazzling',
  'discovering',
  'doodling',
  'dreaming',
  'drifting',
  'enchanting',
  'exploring',
  'finding',
  'floating',
  'fluttering',
  'foraging',
  'forging',
  'frolicking',
  'gathering',
  'giggling',
  'gliding',
  'greeting',
  'growing',
  'hatching',
  'herding',
  'honking',
  'hopping',
  'hugging',
  'humming',
  'imagining',
  'inventing',
  'jingling',
  'juggling',
  'jumping',
  'kindling',
  'knitting',
  'launching',
  'leaping',
  'mapping',
  'marinating',
  'meandering',
  'mixing',
  'moseying',
  'munching',
  'napping',
  'nibbling',
  'noodling',
  'orbiting',
  'painting',
  'percolating',
  'petting',
  'plotting',
  'pondering',
  'popping',
  'prancing',
  'purring',
  'puzzling',
  'questing',
  'riding',
  'roaming',
  'rolling',
  'sauteeing',
  'scribbling',
  'seeking',
  'shimmying',
  'singing',
  'skipping',
  'sleeping',
  'snacking',
  'sniffing',
  'snuggling',
  'soaring',
  'sparking',
  'spinning',
  'splashing',
  'sprouting',
  'squishing',
  'stargazing',
  'stirring',
  'strolling',
  'swimming',
  'swinging',
  'tickling',
  'tinkering',
  'toasting',
  'tumbling',
  'twirling',
  'waddling',
  'wandering',
  'watching',
  'weaving',
  'whistling',
  'wibbling',
  'wiggling',
  'wishing',
  'wobbling',
  'wondering',
  'yawning',
  'zooming',
];

/// Generate a cryptographically random integer in the range [0, max).
int _randomInt(int maxVal) {
  final random = Random.secure();
  return random.nextInt(maxVal);
}

/// Pick a random element from a list.
T _pickRandom<T>(List<T> list) {
  return list[_randomInt(list.length)];
}

/// Generate a random word slug in the format "adjective-verb-noun".
/// Example: "gleaming-brewing-phoenix", "cosmic-pondering-lighthouse"
String generateWordSlug() {
  final adjective = _pickRandom(kAdjectives);
  final verb = _pickRandom(kVerbs);
  final noun = _pickRandom(kNouns);
  return '$adjective-$verb-$noun';
}

/// Generate a shorter random word slug in the format "adjective-noun".
/// Example: "graceful-unicorn", "cosmic-lighthouse"
String generateShortWordSlug() {
  final adjective = _pickRandom(kAdjectives);
  final noun = _pickRandom(kNouns);
  return '$adjective-$noun';
}
