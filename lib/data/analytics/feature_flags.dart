// Feature flags — port of openclaude/src/services/analytics/growthbook.ts.
// Local feature flag evaluation with remote refresh support.

/// Feature flag value.
class FeatureFlag<T> {
  final String key;
  final T defaultValue;
  T _value;
  bool _overridden = false;

  FeatureFlag({required this.key, required this.defaultValue})
      : _value = defaultValue;

  /// Current value.
  T get value => _value;

  /// Whether this flag has been overridden from default.
  bool get isOverridden => _overridden;

  /// Set value from remote config.
  void update(T newValue) {
    _value = newValue;
    _overridden = true;
  }

  /// Reset to default.
  void reset() {
    _value = defaultValue;
    _overridden = false;
  }
}

/// Feature flag service — manages feature flags with local + remote eval.
class FeatureFlagService {
  final Map<String, FeatureFlag> _flags = {};
  final List<void Function()> _listeners = [];

  /// Register a feature flag.
  FeatureFlag<T> register<T>(String key, T defaultValue) {
    final flag = FeatureFlag<T>(key: key, defaultValue: defaultValue);
    _flags[key] = flag;
    return flag;
  }

  /// Get a boolean flag value.
  bool getBool(String key, {bool defaultValue = false}) {
    final flag = _flags[key];
    if (flag is FeatureFlag<bool>) return flag.value;
    return defaultValue;
  }

  /// Get a string flag value.
  String getString(String key, {String defaultValue = ''}) {
    final flag = _flags[key];
    if (flag is FeatureFlag<String>) return flag.value;
    return defaultValue;
  }

  /// Get a numeric flag value.
  num getNum(String key, {num defaultValue = 0}) {
    final flag = _flags[key];
    if (flag is FeatureFlag<num>) return flag.value;
    return defaultValue;
  }

  /// Update flags from remote config (e.g., GrowthBook).
  void updateFromRemote(Map<String, dynamic> config) {
    for (final entry in config.entries) {
      final flag = _flags[entry.key];
      if (flag != null) {
        _updateFlag(flag, entry.value);
      }
    }
    _notifyListeners();
  }

  /// Override a flag locally (for testing/debug).
  void override(String key, dynamic value) {
    final flag = _flags[key];
    if (flag != null) {
      _updateFlag(flag, value);
    }
  }

  /// Register a listener for flag changes.
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Remove a listener.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  void _updateFlag(FeatureFlag flag, dynamic value) {
    if (flag is FeatureFlag<bool> && value is bool) {
      flag.update(value);
    } else if (flag is FeatureFlag<String> && value is String) {
      flag.update(value);
    } else if (flag is FeatureFlag<num> && value is num) {
      flag.update(value);
    }
  }

  /// All registered flag keys.
  Set<String> get keys => _flags.keys.toSet();
}

/// Well-known feature flags (matching GrowthBook keys).
class FeatureFlags {
  static const eventSampling = 'tengu_event_sampling_config';
  static const analyticsKillswitch = 'tengu_frond_boric';
  static const datadogEnabled = 'tengu_log_datadog_events';
  static const promptSuggestions = 'tengu_chomp_inflection';
  static const forkSubagent = 'fork_subagent';
  static const explorePlanAgents = 'explore_plan_agents';
  static const toolSearch = 'tool_search';
  static const verificationAgent = 'verification_agent';
  static const teamMemory = 'team_memory';
  static const voiceMode = 'voice_mode';
  static const buddyMode = 'buddy_mode';
  static const workflowScripts = 'workflow_scripts';
}
