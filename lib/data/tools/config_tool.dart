// ConfigTool — port of neom_claw/src/tools/ConfigTool/.
// Get and set application settings: theme, model, permissions, verbose mode,
// with validation, type coercion, supported-settings registry, and AppState sync.

import 'dart:async';
import 'dart:convert';

import '../../domain/models/permissions.dart';
import 'tool.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const String configToolName = 'Config';

const String configToolDescription = 'Get or set application settings';

// ─── Setting Types ───────────────────────────────────────────────────────────

/// Type of a configuration setting value.
enum SettingType {
  boolean,
  string;

  @override
  String toString() => name;
}

/// Storage source for a configuration setting.
enum SettingSource {
  /// Stored in global config file (~/.neomclaw/config.json).
  global,

  /// Stored in project settings (.neomclaw/settings.json).
  settings,
}

/// AppState keys that can be synced for immediate UI effect.
enum SyncableAppStateKey { verbose, mainLoopModel, thinkingEnabled }

// ─── Setting Configuration ───────────────────────────────────────────────────

/// Configuration metadata for a single setting.
class SettingConfig {
  /// Where the setting is stored.
  final SettingSource source;

  /// Type of the setting value.
  final SettingType type;

  /// Human-readable description.
  final String description;

  /// Path components for nested settings (defaults to key.split('.')).
  final List<String>? path;

  /// Static list of valid options.
  final List<String>? options;

  /// Dynamic options provider.
  final List<String> Function()? getOptions;

  /// AppState key to sync for immediate UI effect.
  final SyncableAppStateKey? appStateKey;

  /// Async validation when writing a value.
  final Future<SettingValidation> Function(dynamic value)? validateOnWrite;

  /// Format value when reading for display.
  final dynamic Function(dynamic value)? formatOnRead;

  const SettingConfig({
    required this.source,
    required this.type,
    required this.description,
    this.path,
    this.options,
    this.getOptions,
    this.appStateKey,
    this.validateOnWrite,
    this.formatOnRead,
  });

  /// Get the effective options list.
  List<String>? get effectiveOptions {
    if (options != null) return options;
    if (getOptions != null) return getOptions!();
    return null;
  }

  /// Get the effective path for this setting key.
  List<String> getPath(String key) => path ?? key.split('.');
}

/// Result of validating a setting value.
class SettingValidation {
  final bool isValid;
  final String? error;

  const SettingValidation.valid() : isValid = true, error = null;
  const SettingValidation.invalid(String message)
    : isValid = false,
      error = message;
}

// ─── Supported Settings Registry ─────────────────────────────────────────────

/// Theme names available in the application.
const List<String> themeNames = [
  'dark',
  'light',
  'light-daltonized',
  'dark-daltonized',
  'system',
  'auto',
];

/// Editor modes for key bindings.
const List<String> editorModes = ['normal', 'vim', 'emacs'];

/// Notification channels.
const List<String> notificationChannels = [
  'iterm2',
  'terminal_bell',
  'terminal_notifier',
  'system',
];

/// Teammate modes.
const List<String> teammateModes = ['tmux', 'in-process', 'auto'];

/// Default permission modes.
const List<String> permissionModes = [
  'default',
  'plan',
  'acceptEdits',
  'dontAsk',
];

/// Default model options.
const List<String> defaultModelOptions = ['sonnet', 'opus', 'haiku'];

/// Registry of all supported settings.
class SupportedSettingsRegistry {
  final Map<String, SettingConfig> _settings = {};

  SupportedSettingsRegistry() {
    _registerDefaults();
  }

  /// Register the default set of supported settings.
  void _registerDefaults() {
    _settings['theme'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.string,
      description: 'Color theme for the UI',
      options: themeNames,
    );

    _settings['editorMode'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.string,
      description: 'Key binding mode',
      options: editorModes,
    );

    _settings['verbose'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.boolean,
      description: 'Show detailed debug output',
      appStateKey: SyncableAppStateKey.verbose,
    );

    _settings['preferredNotifChannel'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.string,
      description: 'Preferred notification channel',
      options: notificationChannels,
    );

    _settings['autoCompactEnabled'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.boolean,
      description: 'Auto-compact when context is full',
    );

    _settings['autoMemoryEnabled'] = SettingConfig(
      source: SettingSource.settings,
      type: SettingType.boolean,
      description: 'Enable auto-memory',
    );

    _settings['autoDreamEnabled'] = SettingConfig(
      source: SettingSource.settings,
      type: SettingType.boolean,
      description: 'Enable background memory consolidation',
    );

    _settings['fileCheckpointingEnabled'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.boolean,
      description: 'Enable file checkpointing for code rewind',
    );

    _settings['showTurnDuration'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.boolean,
      description:
          'Show turn duration message after responses (e.g., "Cooked for 1m 6s")',
    );

    _settings['terminalProgressBarEnabled'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.boolean,
      description: 'Show OSC 9;4 progress indicator in supported terminals',
    );

    _settings['todoFeatureEnabled'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.boolean,
      description: 'Enable todo/task tracking',
    );

    _settings['model'] = SettingConfig(
      source: SettingSource.settings,
      type: SettingType.string,
      description: 'Override the default model',
      appStateKey: SyncableAppStateKey.mainLoopModel,
      getOptions: () => defaultModelOptions,
      formatOnRead: (v) => v ?? 'default',
    );

    _settings['alwaysThinkingEnabled'] = SettingConfig(
      source: SettingSource.settings,
      type: SettingType.boolean,
      description: 'Enable extended thinking (false to disable)',
      appStateKey: SyncableAppStateKey.thinkingEnabled,
    );

    _settings['permissions.defaultMode'] = SettingConfig(
      source: SettingSource.settings,
      type: SettingType.string,
      description: 'Default permission mode for tool usage',
      options: permissionModes,
    );

    _settings['language'] = SettingConfig(
      source: SettingSource.settings,
      type: SettingType.string,
      description:
          'Preferred language for responses and voice dictation '
          '(e.g., "japanese", "spanish")',
    );

    _settings['teammateMode'] = SettingConfig(
      source: SettingSource.global,
      type: SettingType.string,
      description:
          'How to spawn teammates: "tmux" for traditional tmux, '
          '"in-process" for same process, "auto" to choose automatically',
      options: teammateModes,
    );
  }

  /// Register a custom setting.
  void register(String key, SettingConfig config) {
    _settings[key] = config;
  }

  /// Check if a setting key is supported.
  bool isSupported(String key) => _settings.containsKey(key);

  /// Get the config for a setting.
  SettingConfig? getConfig(String key) => _settings[key];

  /// Get all setting keys.
  List<String> getAllKeys() => _settings.keys.toList();

  /// Get valid options for a setting.
  List<String>? getOptionsForSetting(String key) {
    return _settings[key]?.effectiveOptions;
  }

  /// Get the storage path for a setting.
  List<String> getPath(String key) {
    return _settings[key]?.getPath(key) ?? key.split('.');
  }
}

// ─── Config Storage ──────────────────────────────────────────────────────────

/// Abstract interface for reading/writing global config.
abstract class GlobalConfigStore {
  /// Read a value from global config.
  dynamic getValue(String key);

  /// Write a value to global config.
  void setValue(String key, dynamic value);

  /// Get the full config map.
  Map<String, dynamic> getAll();
}

/// Abstract interface for reading/writing project settings.
abstract class SettingsStore {
  /// Read a nested value from settings.
  dynamic getValueAtPath(List<String> path);

  /// Write a nested value to settings.
  SettingValidation setValueAtPath(List<String> path, dynamic value);

  /// Get the full settings map.
  Map<String, dynamic> getAll();
}

/// In-memory global config store for testing/default usage.
class InMemoryGlobalConfigStore implements GlobalConfigStore {
  final Map<String, dynamic> _data = {};

  @override
  dynamic getValue(String key) => _data[key];

  @override
  void setValue(String key, dynamic value) => _data[key] = value;

  @override
  Map<String, dynamic> getAll() => Map.unmodifiable(_data);
}

/// In-memory settings store for testing/default usage.
class InMemorySettingsStore implements SettingsStore {
  final Map<String, dynamic> _data = {};

  @override
  dynamic getValueAtPath(List<String> path) {
    dynamic current = _data;
    for (final key in path) {
      if (current is Map && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  @override
  SettingValidation setValueAtPath(List<String> path, dynamic value) {
    if (path.isEmpty) {
      return const SettingValidation.invalid('Invalid setting path');
    }

    Map<String, dynamic> current = _data;
    for (var i = 0; i < path.length - 1; i++) {
      final key = path[i];
      if (!current.containsKey(key) || current[key] is! Map) {
        current[key] = <String, dynamic>{};
      }
      current = current[key] as Map<String, dynamic>;
    }
    current[path.last] = value;
    return const SettingValidation.valid();
  }

  @override
  Map<String, dynamic> getAll() => Map.unmodifiable(_data);
}

// ─── ConfigTool Input / Output ───────────────────────────────────────────────

/// Input for the ConfigTool.
class ConfigToolInput {
  final String setting;
  final dynamic value; // String, bool, num, or null (for GET)

  const ConfigToolInput({required this.setting, this.value});

  factory ConfigToolInput.fromJson(Map<String, dynamic> json) =>
      ConfigToolInput(setting: json['setting'] as String, value: json['value']);

  /// Whether this is a GET operation (no value provided).
  bool get isGet => value == null;
}

/// Output for the ConfigTool.
class ConfigToolOutput {
  final bool success;
  final String? operation; // 'get' or 'set'
  final String? setting;
  final dynamic value;
  final dynamic previousValue;
  final dynamic newValue;
  final String? error;

  const ConfigToolOutput({
    required this.success,
    this.operation,
    this.setting,
    this.value,
    this.previousValue,
    this.newValue,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    if (operation != null) 'operation': operation,
    if (setting != null) 'setting': setting,
    if (value != null) 'value': value,
    if (previousValue != null) 'previousValue': previousValue,
    if (newValue != null) 'newValue': newValue,
    if (error != null) 'error': error,
  };
}

// ─── Build Nested Object ─────────────────────────────────────────────────────

/// Build a nested map from a path and value.
/// E.g., ['permissions', 'defaultMode'], 'plan' =>
///   {'permissions': {'defaultMode': 'plan'}}
Map<String, dynamic> buildNestedObject(List<String> path, dynamic value) {
  if (path.isEmpty) return {};
  final key = path.first;
  if (path.length == 1) return {key: value};
  return {key: buildNestedObject(path.sublist(1), value)};
}

// ─── ConfigTool Implementation ───────────────────────────────────────────────

/// The ConfigTool — get or set application settings.
class ConfigTool extends Tool {
  final SupportedSettingsRegistry _registry;
  final GlobalConfigStore _globalConfig;
  final SettingsStore _settings;

  /// Callback for syncing values to AppState for immediate UI effect.
  final void Function(SyncableAppStateKey key, dynamic value)? onAppStateSync;

  ConfigTool({
    SupportedSettingsRegistry? registry,
    GlobalConfigStore? globalConfig,
    SettingsStore? settings,
    this.onAppStateSync,
  }) : _registry = registry ?? SupportedSettingsRegistry(),
       _globalConfig = globalConfig ?? InMemoryGlobalConfigStore(),
       _settings = settings ?? InMemorySettingsStore();

  @override
  String get name => configToolName;

  @override
  String get description => configToolDescription;

  @override
  String get userFacingName => 'Config';

  @override
  bool get shouldDefer => true;

  @override
  bool get isConcurrencySafe => true;

  @override
  int? get maxResultSizeChars => 100000;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'setting': {
        'type': 'string',
        'description':
            'The setting key (e.g., "theme", "model", '
            '"permissions.defaultMode")',
      },
      'value': {
        'description': 'The new value. Omit to get current value.',
        'oneOf': [
          {'type': 'string'},
          {'type': 'boolean'},
          {'type': 'number'},
        ],
      },
    },
    'required': ['setting'],
    'additionalProperties': false,
  };

  @override
  String get prompt => _generatePrompt();

  /// Generate a dynamic prompt listing available settings.
  String _generatePrompt() {
    final keys = _registry.getAllKeys();
    final settingsList = keys
        .map((key) {
          final config = _registry.getConfig(key)!;
          var desc = '  - $key (${config.type}): ${config.description}';
          final opts = config.effectiveOptions;
          if (opts != null && opts.isNotEmpty) {
            desc += ' [${opts.join(", ")}]';
          }
          return desc;
        })
        .join('\n');

    return '''Get or set application settings.

Available settings:
$settingsList

To read a setting, provide only the setting key.
To write a setting, provide both the setting key and the new value.
''';
  }

  /// Whether this config operation is read-only (no value being set).
  bool isReadOnlyOperation(Map<String, dynamic> input) {
    return input['value'] == null;
  }

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, dynamic> input,
    ToolPermissionContext permContext,
  ) async {
    // Auto-allow reading configs.
    if (input['value'] == null) {
      return const AllowDecision(PermissionAllowDecision());
    }
    final setting = input['setting'] as String;
    final value = input['value'];
    return AskDecision(
      PermissionAskDecision(message: 'Set $setting to ${jsonEncode(value)}'),
    );
  }

  @override
  String toAutoClassifierInput(Map<String, dynamic> input) {
    final setting = input['setting'] as String;
    final value = input['value'];
    if (value == null) return setting;
    return '$setting = $value';
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = ConfigToolInput.fromJson(input);
    final setting = parsed.setting;

    // 1. Check if setting is supported.
    if (!_registry.isSupported(setting)) {
      return _errorResult('Unknown setting: "$setting"');
    }

    final config = _registry.getConfig(setting)!;
    final path = _registry.getPath(setting);

    // 2. GET operation.
    if (parsed.isGet) {
      final currentValue = _getValue(config.source, path);
      final displayValue = config.formatOnRead != null
          ? config.formatOnRead!(currentValue)
          : currentValue;

      return _successResult(
        ConfigToolOutput(
          success: true,
          operation: 'get',
          setting: setting,
          value: displayValue,
        ),
      );
    }

    // 3. SET operation.
    var finalValue = parsed.value;

    // Coerce and validate boolean values.
    if (config.type == SettingType.boolean) {
      if (finalValue is String) {
        final lower = finalValue.toLowerCase().trim();
        if (lower == 'true') {
          finalValue = true;
        } else if (lower == 'false') {
          finalValue = false;
        }
      }
      if (finalValue is! bool) {
        return _errorResult(
          '$setting requires true or false.',
          operation: 'set',
          setting: setting,
        );
      }
    }

    // Check options.
    final options = _registry.getOptionsForSetting(setting);
    if (options != null && !options.contains(finalValue.toString())) {
      return _errorResult(
        'Invalid value "$finalValue". Options: ${options.join(", ")}',
        operation: 'set',
        setting: setting,
      );
    }

    // Async validation.
    if (config.validateOnWrite != null) {
      final validation = await config.validateOnWrite!(finalValue);
      if (!validation.isValid) {
        return _errorResult(
          validation.error ?? 'Validation failed',
          operation: 'set',
          setting: setting,
        );
      }
    }

    final previousValue = _getValue(config.source, path);

    // 4. Write to storage.
    try {
      if (config.source == SettingSource.global) {
        final key = path.first;
        _globalConfig.setValue(key, finalValue);
      } else {
        final result = _settings.setValueAtPath(path, finalValue);
        if (!result.isValid) {
          return _errorResult(
            result.error ?? 'Failed to update setting',
            operation: 'set',
            setting: setting,
          );
        }
      }

      // 5. Sync to AppState if needed.
      if (config.appStateKey != null && onAppStateSync != null) {
        onAppStateSync!(config.appStateKey!, finalValue);
      }

      return _successResult(
        ConfigToolOutput(
          success: true,
          operation: 'set',
          setting: setting,
          previousValue: previousValue,
          newValue: finalValue,
        ),
      );
    } catch (e) {
      return _errorResult('$e', operation: 'set', setting: setting);
    }
  }

  /// Read a value from the appropriate store.
  dynamic _getValue(SettingSource source, List<String> path) {
    if (source == SettingSource.global) {
      final key = path.first;
      return _globalConfig.getValue(key);
    }
    return _settings.getValueAtPath(path);
  }

  /// Create a success ToolResult from ConfigToolOutput.
  ToolResult _successResult(ConfigToolOutput output) {
    String content;
    if (output.operation == 'get') {
      content = '${output.setting} = ${jsonEncode(output.value)}';
    } else {
      content = 'Set ${output.setting} to ${jsonEncode(output.newValue)}';
    }
    return ToolResult.success(content, metadata: output.toJson());
  }

  /// Create an error ToolResult from ConfigToolOutput.
  ToolResult _errorResult(String error, {String? operation, String? setting}) {
    return ToolResult(
      content: 'Error: $error',
      isError: true,
      metadata: ConfigToolOutput(
        success: false,
        operation: operation,
        setting: setting,
        error: error,
      ).toJson(),
    );
  }

  /// The settings registry used by this tool.
  SupportedSettingsRegistry get registry => _registry;

  /// The global config store.
  GlobalConfigStore get globalConfig => _globalConfig;

  /// The settings store.
  SettingsStore get settingsStore => _settings;
}
