/// Configuration management service for Flutter Claw, ported from OpenClaude.
///
/// Supports scoped configuration (global, project, session), multiple sources
/// (file, environment, CLI, API, defaults), reactive watching, validation,
/// and import/export — including migration from Claude Code's `~/.claude/`
/// directory layout.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The scope at which a configuration value is applied.
enum ConfigScope {
  /// Machine-wide settings stored in `~/.claw/config.json`.
  global,

  /// Project-level settings stored in `.claw/config.json` relative to the
  /// project root.
  project,

  /// Ephemeral settings that last for the current session only.
  session,
}

/// Where a configuration value originated.
enum ConfigSource {
  /// Loaded from a JSON / YAML configuration file.
  file,

  /// Read from an environment variable.
  env,

  /// Passed via command-line arguments.
  cli,

  /// Received from the Anthropic API (e.g. model capabilities).
  api,

  /// The built-in default value.
  default_,
}

// ---------------------------------------------------------------------------
// Config Entry
// ---------------------------------------------------------------------------

/// A single typed configuration entry with metadata about its origin.
class ConfigEntry<T> {
  const ConfigEntry({
    required this.key,
    required this.value,
    this.scope = ConfigScope.global,
    this.source = ConfigSource.default_,
    this.description = '',
    this.validator,
  });

  /// Dotted key path, e.g. `"model"` or `"mcp.servers"`.
  final String key;

  /// The resolved value.
  final T value;

  /// The scope this entry belongs to.
  final ConfigScope scope;

  /// How this value was originally set.
  final ConfigSource source;

  /// Human-readable description of the entry.
  final String description;

  /// Optional validator that returns `true` when [value] is acceptable.
  final bool Function(T value)? validator;

  /// Whether [value] passes the optional [validator].
  bool get isValid => validator == null || validator!(value);

  /// Return a copy with replaced fields.
  ConfigEntry<T> copyWith({
    String? key,
    T? value,
    ConfigScope? scope,
    ConfigSource? source,
    String? description,
    bool Function(T)? validator,
  }) {
    return ConfigEntry<T>(
      key: key ?? this.key,
      value: value ?? this.value,
      scope: scope ?? this.scope,
      source: source ?? this.source,
      description: description ?? this.description,
      validator: validator ?? this.validator,
    );
  }

  @override
  String toString() => 'ConfigEntry($key=$value, scope=$scope, source=$source)';
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Result of validating the entire configuration.
class ConfigValidation {
  const ConfigValidation({required this.isValid, required this.errors});

  /// Whether all entries passed validation.
  final bool isValid;

  /// Human-readable error descriptions for invalid entries.
  final List<String> errors;

  @override
  String toString() => 'ConfigValidation(valid=$isValid, errors=${errors.length})';
}

// ---------------------------------------------------------------------------
// Schema
// ---------------------------------------------------------------------------

/// Describes the expected shape and constraints for configuration.
class ConfigSchema {
  const ConfigSchema({required this.entries});

  /// Map of dotted key paths to their schema definitions.
  final Map<String, ConfigEntry> entries;

  /// Validate a flat config map against this schema, returning a
  /// [ConfigValidation] with accumulated errors.
  ConfigValidation validate(Map<String, dynamic> config) {
    final errors = <String>[];
    for (final entry in entries.values) {
      if (config.containsKey(entry.key)) {
        final raw = config[entry.key];
        if (entry.validator != null) {
          try {
            if (!entry.validator!(raw)) {
              errors.add('${entry.key}: value "$raw" failed validation');
            }
          } catch (e) {
            errors.add('${entry.key}: validator threw — $e');
          }
        }
      }
    }
    return ConfigValidation(isValid: errors.isEmpty, errors: errors);
  }
}

// ---------------------------------------------------------------------------
// Diff
// ---------------------------------------------------------------------------

/// Represents a difference between two configuration values for the same key.
class ConfigDiff {
  const ConfigDiff({
    required this.key,
    required this.oldValue,
    required this.newValue,
    required this.scope,
  });

  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final ConfigScope scope;

  @override
  String toString() => 'ConfigDiff($key: $oldValue -> $newValue [$scope])';
}

// ---------------------------------------------------------------------------
// Change Event
// ---------------------------------------------------------------------------

/// Emitted whenever a configuration value changes.
class ConfigChangeEvent {
  const ConfigChangeEvent({
    required this.key,
    required this.oldValue,
    required this.newValue,
    required this.scope,
    required this.timestamp,
  });

  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final ConfigScope scope;
  final DateTime timestamp;

  @override
  String toString() =>
      'ConfigChangeEvent($key: $oldValue -> $newValue [$scope] @ $timestamp)';
}

// ---------------------------------------------------------------------------
// Predefined Config Keys
// ---------------------------------------------------------------------------

/// Well-known configuration keys used throughout Claw.
abstract final class ConfigKeys {
  static const String apiKey = 'apiKey';
  static const String model = 'model';
  static const String baseUrl = 'baseUrl';
  static const String maxTokens = 'maxTokens';
  static const String temperature = 'temperature';
  static const String permissionMode = 'permissionMode';
  static const String theme = 'theme';
  static const String vimMode = 'vimMode';
  static const String telemetryEnabled = 'telemetryEnabled';
  static const String mcpServers = 'mcpServers';
  static const String systemPrompt = 'systemPrompt';
  static const String allowedTools = 'allowedTools';
  static const String deniedTools = 'deniedTools';
  static const String autoApprovePatterns = 'autoApprovePatterns';
  static const String historyDir = 'historyDir';
  static const String logLevel = 'logLevel';
  static const String timeout = 'timeout';
  static const String retryCount = 'retryCount';
  static const String projectRoot = 'projectRoot';
  static const String shell = 'shell';
  static const String editor = 'editor';
  static const String diffTool = 'diffTool';
  static const String locale = 'locale';
}

/// Map from environment variable names to their corresponding config keys.
const Map<String, String> _envMapping = {
  'ANTHROPIC_API_KEY': ConfigKeys.apiKey,
  'CLAUDE_MODEL': ConfigKeys.model,
  'ANTHROPIC_BASE_URL': ConfigKeys.baseUrl,
  'CLAUDE_MAX_TOKENS': ConfigKeys.maxTokens,
  'CLAUDE_TEMPERATURE': ConfigKeys.temperature,
  'CLAUDE_PERMISSION_MODE': ConfigKeys.permissionMode,
  'CLAUDE_THEME': ConfigKeys.theme,
  'CLAUDE_VIM_MODE': ConfigKeys.vimMode,
  'CLAUDE_TELEMETRY': ConfigKeys.telemetryEnabled,
  'CLAUDE_LOG_LEVEL': ConfigKeys.logLevel,
  'CLAUDE_TIMEOUT': ConfigKeys.timeout,
  'CLAUDE_SHELL': ConfigKeys.shell,
};

// ---------------------------------------------------------------------------
// Default values
// ---------------------------------------------------------------------------

const Map<String, dynamic> _defaults = {
  ConfigKeys.model: 'claude-sonnet-4-20250514',
  ConfigKeys.baseUrl: 'https://api.anthropic.com',
  ConfigKeys.maxTokens: 8192,
  ConfigKeys.temperature: 1.0,
  ConfigKeys.permissionMode: 'prompt',
  ConfigKeys.theme: 'dark-default',
  ConfigKeys.vimMode: false,
  ConfigKeys.telemetryEnabled: true,
  ConfigKeys.logLevel: 'info',
  ConfigKeys.timeout: 120000,
  ConfigKeys.retryCount: 3,
  ConfigKeys.shell: '/bin/bash',
  ConfigKeys.mcpServers: <String, dynamic>{},
  ConfigKeys.allowedTools: <String>[],
  ConfigKeys.deniedTools: <String>[],
  ConfigKeys.autoApprovePatterns: <String>[],
};

// ---------------------------------------------------------------------------
// Config Service
// ---------------------------------------------------------------------------

/// Central configuration service for Claw.
///
/// Manages layered configuration across [ConfigScope.global],
/// [ConfigScope.project], and [ConfigScope.session] scopes. Values set in a
/// narrower scope override broader ones (session > project > global > default).
///
/// Usage:
/// ```dart
/// final config = ConfigService();
/// await config.loadFromFile(config.getConfigPath(scope: ConfigScope.global));
/// config.loadFromEnv();
///
/// final model = config.get<String>(ConfigKeys.model);
/// config.watch<String>(ConfigKeys.model).listen((v) => print('model=$v'));
/// ```
class ConfigService {
  ConfigService();

  /// Layered storage: scope -> key -> value.
  final Map<ConfigScope, Map<String, dynamic>> _store = {
    ConfigScope.global: {},
    ConfigScope.project: {},
    ConfigScope.session: {},
  };

  /// Source tracking: scope -> key -> source.
  final Map<ConfigScope, Map<String, ConfigSource>> _sources = {
    ConfigScope.global: {},
    ConfigScope.project: {},
    ConfigScope.session: {},
  };

  /// Broadcast controller for all config changes.
  final StreamController<ConfigChangeEvent> _changeController =
      StreamController<ConfigChangeEvent>.broadcast();

  // -----------------------------------------------------------------------
  // Core CRUD
  // -----------------------------------------------------------------------

  /// Retrieve a typed value for [key].
  ///
  /// Resolution order: session > project > global > [defaultValue] > built-in
  /// default. If [scope] is given, only that scope is searched.
  T get<T>(String key, {ConfigScope? scope, T? defaultValue}) {
    if (scope != null) {
      final map = _store[scope]!;
      if (map.containsKey(key)) return map[key] as T;
      if (defaultValue != null) return defaultValue;
      if (_defaults.containsKey(key)) return _defaults[key] as T;
      throw StateError('Config key "$key" not found in scope $scope');
    }

    // Walk scopes from narrowest to broadest.
    for (final s in [ConfigScope.session, ConfigScope.project, ConfigScope.global]) {
      final map = _store[s]!;
      if (map.containsKey(key)) return map[key] as T;
    }
    if (defaultValue != null) return defaultValue;
    if (_defaults.containsKey(key)) return _defaults[key] as T;
    throw StateError('Config key "$key" not found');
  }

  /// Try to get a value, returning `null` instead of throwing.
  T? tryGet<T>(String key, {ConfigScope? scope}) {
    try {
      return get<T>(key, scope: scope);
    } catch (_) {
      return null;
    }
  }

  /// Set a typed value for [key] in the given [scope] (defaults to session).
  void set<T>(String key, T value, {ConfigScope scope = ConfigScope.session}) {
    final old = tryGet<T>(key, scope: scope);
    _store[scope]![key] = value;
    _sources[scope]![key] = ConfigSource.cli;
    _emitChange(key, old, value, scope);
  }

  /// Remove a key from the given [scope].
  void remove(String key, {ConfigScope scope = ConfigScope.session}) {
    final old = tryGet(key, scope: scope);
    _store[scope]!.remove(key);
    _sources[scope]!.remove(key);
    _emitChange(key, old, null, scope);
  }

  /// Whether [key] exists in [scope] (or any scope if [scope] is null).
  bool has(String key, {ConfigScope? scope}) {
    if (scope != null) return _store[scope]!.containsKey(key);
    return _store.values.any((m) => m.containsKey(key));
  }

  /// Return all key-value pairs for [scope] (defaults to merged view).
  Map<String, dynamic> getAll({ConfigScope? scope}) {
    if (scope != null) return Map.unmodifiable(_store[scope]!);
    // Merge: defaults < global < project < session.
    final merged = Map<String, dynamic>.from(_defaults);
    merged.addAll(_store[ConfigScope.global]!);
    merged.addAll(_store[ConfigScope.project]!);
    merged.addAll(_store[ConfigScope.session]!);
    return Map.unmodifiable(merged);
  }

  /// Merge [overrides] into the given [scope].
  void merge(Map<String, dynamic> overrides, {ConfigScope scope = ConfigScope.session}) {
    for (final entry in overrides.entries) {
      set(entry.key, entry.value, scope: scope);
    }
  }

  /// Reset configuration.
  ///
  /// If [key] is given, only that key is reset within [scope]. Otherwise the
  /// entire [scope] is cleared. If [scope] is null, all scopes are cleared.
  void reset({ConfigScope? scope, String? key}) {
    if (scope != null && key != null) {
      remove(key, scope: scope);
      return;
    }
    if (scope != null) {
      final old = Map<String, dynamic>.from(_store[scope]!);
      _store[scope]!.clear();
      _sources[scope]!.clear();
      for (final k in old.keys) {
        _emitChange(k, old[k], null, scope);
      }
      return;
    }
    // Reset all scopes.
    for (final s in ConfigScope.values) {
      reset(scope: s);
    }
  }

  // -----------------------------------------------------------------------
  // Watching
  // -----------------------------------------------------------------------

  /// Observe changes to a specific [key], emitting the new value whenever it
  /// changes in any scope.
  Stream<T> watch<T>(String key) {
    return _changeController.stream
        .where((e) => e.key == key)
        .map((e) => e.newValue as T);
  }

  /// Stream of all configuration change events.
  Stream<ConfigChangeEvent> get changes => _changeController.stream;

  // -----------------------------------------------------------------------
  // Validation
  // -----------------------------------------------------------------------

  /// Validate the merged configuration using built-in rules.
  ConfigValidation validate() {
    final errors = <String>[];
    final all = getAll();

    // Required non-empty string checks.
    if (all[ConfigKeys.apiKey] == null || (all[ConfigKeys.apiKey] as String).isEmpty) {
      errors.add('${ConfigKeys.apiKey}: API key is required');
    }

    // Numeric range checks.
    final maxTokens = all[ConfigKeys.maxTokens];
    if (maxTokens is int && (maxTokens < 1 || maxTokens > 200000)) {
      errors.add('${ConfigKeys.maxTokens}: must be between 1 and 200000');
    }

    final temp = all[ConfigKeys.temperature];
    if (temp is num && (temp < 0.0 || temp > 2.0)) {
      errors.add('${ConfigKeys.temperature}: must be between 0.0 and 2.0');
    }

    // Permission mode must be one of known values.
    final pm = all[ConfigKeys.permissionMode];
    if (pm is String && !{'prompt', 'auto', 'deny'}.contains(pm)) {
      errors.add('${ConfigKeys.permissionMode}: must be prompt, auto, or deny');
    }

    // Log level.
    final ll = all[ConfigKeys.logLevel];
    if (ll is String && !{'debug', 'info', 'warn', 'error', 'silent'}.contains(ll)) {
      errors.add('${ConfigKeys.logLevel}: must be debug, info, warn, error, or silent');
    }

    return ConfigValidation(isValid: errors.isEmpty, errors: errors);
  }

  // -----------------------------------------------------------------------
  // File I/O
  // -----------------------------------------------------------------------

  /// Load configuration from a JSON file at [path] into the given [scope].
  ///
  /// Returns `false` if the file does not exist or cannot be parsed.
  Future<bool> loadFromFile(String path, {ConfigScope scope = ConfigScope.global}) async {
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      final content = await file.readAsString();
      final map = json.decode(content) as Map<String, dynamic>;
      for (final entry in map.entries) {
        _store[scope]![entry.key] = entry.value;
        _sources[scope]![entry.key] = ConfigSource.file;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Save configuration for [scope] to a JSON file at [path].
  Future<void> saveToFile(String path, {ConfigScope scope = ConfigScope.global}) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final data = _store[scope]!;
    // Filter out sensitive keys from the written file.
    final safe = Map<String, dynamic>.from(data);
    safe.remove(ConfigKeys.apiKey);
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(safe));
  }

  /// Read well-known environment variables and store them in the global scope.
  void loadFromEnv({Map<String, String>? overrideEnv}) {
    final env = overrideEnv ?? Platform.environment;
    for (final entry in _envMapping.entries) {
      final envValue = env[entry.key];
      if (envValue != null && envValue.isNotEmpty) {
        final configKey = entry.value;
        dynamic parsed = envValue;
        // Attempt numeric / bool coercion.
        if (int.tryParse(envValue) != null) {
          parsed = int.parse(envValue);
        } else if (double.tryParse(envValue) != null) {
          parsed = double.parse(envValue);
        } else if (envValue.toLowerCase() == 'true') {
          parsed = true;
        } else if (envValue.toLowerCase() == 'false') {
          parsed = false;
        }
        _store[ConfigScope.global]![configKey] = parsed;
        _sources[ConfigScope.global]![configKey] = ConfigSource.env;
      }
    }
  }

  /// Return the canonical file path for a configuration scope.
  ///
  /// - [ConfigScope.global]: `~/.claw/config.json`
  /// - [ConfigScope.project]: `.claw/config.json` (relative to cwd or
  ///   [projectRoot])
  /// - [ConfigScope.session]: in-memory only, returns empty string.
  String getConfigPath({ConfigScope scope = ConfigScope.global, String? projectRoot}) {
    switch (scope) {
      case ConfigScope.global:
        final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
        return '$home/.claw/config.json';
      case ConfigScope.project:
        final root = projectRoot ?? Directory.current.path;
        return '$root/.claw/config.json';
      case ConfigScope.session:
        return ''; // session config is ephemeral
    }
  }

  // -----------------------------------------------------------------------
  // Diff
  // -----------------------------------------------------------------------

  /// Compare configuration between two scopes and return the differences.
  List<ConfigDiff> diff(ConfigScope scope1, ConfigScope scope2) {
    final map1 = _store[scope1]!;
    final map2 = _store[scope2]!;
    final allKeys = {...map1.keys, ...map2.keys};
    final diffs = <ConfigDiff>[];

    for (final key in allKeys) {
      final v1 = map1[key];
      final v2 = map2[key];
      if (v1 != v2) {
        diffs.add(ConfigDiff(key: key, oldValue: v1, newValue: v2, scope: scope1));
      }
    }
    return diffs;
  }

  // -----------------------------------------------------------------------
  // Import / Export
  // -----------------------------------------------------------------------

  /// Attempt to migrate settings from an existing Claude Code installation at
  /// `~/.claude/`.
  ///
  /// This reads `~/.claude/settings.json` (if present) and maps known keys
  /// into the Claw configuration format.
  Future<bool> importFromClaudeCode() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) return false;
    final settingsFile = File('$home/.claude/settings.json');
    if (!await settingsFile.exists()) return false;

    try {
      final content = await settingsFile.readAsString();
      final map = json.decode(content) as Map<String, dynamic>;

      // Map Claude Code keys to Claw keys where possible.
      const mapping = <String, String>{
        'model': ConfigKeys.model,
        'apiKey': ConfigKeys.apiKey,
        'permissions': ConfigKeys.permissionMode,
        'theme': ConfigKeys.theme,
        'telemetry': ConfigKeys.telemetryEnabled,
        'maxTokens': ConfigKeys.maxTokens,
        'systemPrompt': ConfigKeys.systemPrompt,
        'allowedTools': ConfigKeys.allowedTools,
        'mcpServers': ConfigKeys.mcpServers,
      };

      for (final entry in mapping.entries) {
        if (map.containsKey(entry.key)) {
          _store[ConfigScope.global]![entry.value] = map[entry.key];
          _sources[ConfigScope.global]![entry.value] = ConfigSource.file;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Export configuration to a JSON or YAML string.
  ///
  /// Only JSON is implemented; YAML support is a future extension.
  String exportConfig({
    ConfigScope? scope,
    String format = 'json',
  }) {
    final data = scope != null ? _store[scope]! : getAll();
    // Strip sensitive keys.
    final safe = Map<String, dynamic>.from(data);
    safe.remove(ConfigKeys.apiKey);

    if (format == 'json') {
      return const JsonEncoder.withIndent('  ').convert(safe);
    }
    // Fallback to JSON for unsupported formats.
    return const JsonEncoder.withIndent('  ').convert(safe);
  }

  // -----------------------------------------------------------------------
  // Source inspection
  // -----------------------------------------------------------------------

  /// Return the [ConfigSource] for a specific key within a scope.
  ConfigSource? getSource(String key, {ConfigScope scope = ConfigScope.global}) {
    return _sources[scope]?[key];
  }

  /// Build a [ConfigEntry] for inspection of a single key.
  ConfigEntry<T>? getEntry<T>(String key, {ConfigScope? scope}) {
    final effectiveScope = scope ?? _resolveScope(key);
    if (effectiveScope == null) return null;
    final value = _store[effectiveScope]![key];
    if (value == null) return null;
    return ConfigEntry<T>(
      key: key,
      value: value as T,
      scope: effectiveScope,
      source: _sources[effectiveScope]?[key] ?? ConfigSource.default_,
    );
  }

  // -----------------------------------------------------------------------
  // Internals
  // -----------------------------------------------------------------------

  ConfigScope? _resolveScope(String key) {
    for (final s in [ConfigScope.session, ConfigScope.project, ConfigScope.global]) {
      if (_store[s]!.containsKey(key)) return s;
    }
    return null;
  }

  void _emitChange(String key, dynamic oldValue, dynamic newValue, ConfigScope scope) {
    if (oldValue == newValue) return;
    _changeController.add(ConfigChangeEvent(
      key: key,
      oldValue: oldValue,
      newValue: newValue,
      scope: scope,
      timestamp: DateTime.now(),
    ));
  }

  /// Release resources.
  void dispose() {
    _changeController.close();
  }
}
