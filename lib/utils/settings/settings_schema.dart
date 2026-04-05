// Settings schema — port of neomage/src/utils/settings/.
// Hierarchical settings loading, validation, merging, and change detection.

import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

/// Settings sources in priority order.
enum SettingsSource {
  policy, // MDM-managed (highest priority)
  project, // .neomage/settings.json
  local, // .neomage/settings.local.json (gitignored)
  user, // ~/.neomage/settings.json
}

/// Sandbox settings.
class SandboxSettings {
  final bool enabled;
  final List<String> excludedCommands;
  final List<String> readPaths;
  final List<String> writePaths;
  final bool networkEnabled;

  const SandboxSettings({
    this.enabled = false,
    this.excludedCommands = const [],
    this.readPaths = const [],
    this.writePaths = const [],
    this.networkEnabled = true,
  });

  factory SandboxSettings.fromJson(Map<String, dynamic> json) =>
      SandboxSettings(
        enabled: json['enabled'] as bool? ?? false,
        excludedCommands:
            (json['excludedCommands'] as List?)?.cast<String>() ?? [],
        readPaths: (json['readPaths'] as List?)?.cast<String>() ?? [],
        writePaths: (json['writePaths'] as List?)?.cast<String>() ?? [],
        networkEnabled: json['networkEnabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    if (excludedCommands.isNotEmpty) 'excludedCommands': excludedCommands,
    if (readPaths.isNotEmpty) 'readPaths': readPaths,
    if (writePaths.isNotEmpty) 'writePaths': writePaths,
    'networkEnabled': networkEnabled,
  };
}

/// Hook settings entry.
class HookSettingsEntry {
  final String event;
  final List<Map<String, dynamic>> hooks;

  const HookSettingsEntry({required this.event, required this.hooks});
}

/// Permission settings.
class PermissionSettings {
  final List<String> allow;
  final List<String> deny;
  final List<String> ask;
  final String? defaultMode;
  final bool? disableBypassPermissionsMode;
  final List<String> additionalDirectories;

  const PermissionSettings({
    this.allow = const [],
    this.deny = const [],
    this.ask = const [],
    this.defaultMode,
    this.disableBypassPermissionsMode,
    this.additionalDirectories = const [],
  });

  factory PermissionSettings.fromJson(Map<String, dynamic> json) =>
      PermissionSettings(
        allow: (json['allow'] as List?)?.cast<String>() ?? [],
        deny: (json['deny'] as List?)?.cast<String>() ?? [],
        ask: (json['ask'] as List?)?.cast<String>() ?? [],
        defaultMode: json['defaultMode'] as String?,
        disableBypassPermissionsMode:
            json['disableBypassPermissionsMode'] == 'disable',
        additionalDirectories:
            (json['additionalDirectories'] as List?)?.cast<String>() ?? [],
      );

  Map<String, dynamic> toJson() => {
    if (allow.isNotEmpty) 'allow': allow,
    if (deny.isNotEmpty) 'deny': deny,
    if (ask.isNotEmpty) 'ask': ask,
    if (defaultMode != null) 'defaultMode': defaultMode,
    if (disableBypassPermissionsMode == true)
      'disableBypassPermissionsMode': 'disable',
    if (additionalDirectories.isNotEmpty)
      'additionalDirectories': additionalDirectories,
  };
}

/// Full settings JSON structure.
class SettingsJson {
  final String? model;
  final PermissionSettings permissions;
  final SandboxSettings sandbox;
  final Map<String, dynamic>? hooks;
  final List<String> installedPlugins;
  final Map<String, String> environmentVariables;
  final Map<String, String> modelOverrides;
  final List<String> availableModels;
  final bool allowManagedPermissionRulesOnly;
  final bool syntaxHighlightingEnabled;
  final String? theme;
  final String? outputStyle;
  final Map<String, dynamic> raw;

  const SettingsJson({
    this.model,
    this.permissions = const PermissionSettings(),
    this.sandbox = const SandboxSettings(),
    this.hooks,
    this.installedPlugins = const [],
    this.environmentVariables = const {},
    this.modelOverrides = const {},
    this.availableModels = const [],
    this.allowManagedPermissionRulesOnly = false,
    this.syntaxHighlightingEnabled = true,
    this.theme,
    this.outputStyle,
    this.raw = const {},
  });

  factory SettingsJson.fromJson(Map<String, dynamic> json) {
    return SettingsJson(
      model: json['model'] as String?,
      permissions: json['permissions'] is Map<String, dynamic>
          ? PermissionSettings.fromJson(
              json['permissions'] as Map<String, dynamic>,
            )
          : const PermissionSettings(),
      sandbox: json['sandbox'] is Map<String, dynamic>
          ? SandboxSettings.fromJson(json['sandbox'] as Map<String, dynamic>)
          : const SandboxSettings(),
      hooks: json['hooks'] as Map<String, dynamic>?,
      installedPlugins: (json['plugins'] is Map<String, dynamic>)
          ? ((json['plugins'] as Map<String, dynamic>)['installed'] as List?)
                    ?.cast<String>() ??
                []
          : [],
      environmentVariables:
          (json['environmentVariables'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          {},
      modelOverrides:
          (json['modelOverrides'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          {},
      availableModels: (json['availableModels'] as List?)?.cast<String>() ?? [],
      allowManagedPermissionRulesOnly:
          json['allowManagedPermissionRulesOnly'] as bool? ?? false,
      syntaxHighlightingEnabled:
          json['syntaxHighlightingEnabled'] as bool? ?? true,
      theme: json['theme'] as String?,
      outputStyle: json['outputStyle'] as String?,
      raw: json,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (model != null) json['model'] = model;
    final perms = permissions.toJson();
    if (perms.isNotEmpty) json['permissions'] = perms;
    final sb = sandbox.toJson();
    if (sb.isNotEmpty) json['sandbox'] = sb;
    if (hooks != null) json['hooks'] = hooks;
    if (installedPlugins.isNotEmpty) {
      json['plugins'] = {'installed': installedPlugins};
    }
    if (environmentVariables.isNotEmpty) {
      json['environmentVariables'] = environmentVariables;
    }
    if (modelOverrides.isNotEmpty) json['modelOverrides'] = modelOverrides;
    if (availableModels.isNotEmpty) json['availableModels'] = availableModels;
    if (allowManagedPermissionRulesOnly) {
      json['allowManagedPermissionRulesOnly'] = true;
    }
    if (!syntaxHighlightingEnabled) {
      json['syntaxHighlightingEnabled'] = false;
    }
    if (theme != null) json['theme'] = theme;
    if (outputStyle != null) json['outputStyle'] = outputStyle;
    return json;
  }
}

// ── Settings Loading ──

/// Load settings from a file path.
Future<SettingsJson?> loadSettingsFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;

  try {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return SettingsJson.fromJson(json);
  } catch (_) {
    return null;
  }
}

/// Load and merge settings from all sources.
Future<SettingsJson> loadMergedSettings({
  required String projectDir,
  required String userConfigDir,
  String? policyPath,
}) async {
  // Load each source
  final policy = policyPath != null ? await loadSettingsFile(policyPath) : null;
  final project = await loadSettingsFile('$projectDir/.neomage/settings.json');
  final local = await loadSettingsFile(
    '$projectDir/.neomage/settings.local.json',
  );
  final user = await loadSettingsFile('$userConfigDir/settings.json');

  // Merge (later sources fill gaps, earlier sources take priority)
  return mergeSettings([?policy, ?project, ?local, ?user]);
}

/// Merge multiple settings (first takes priority).
SettingsJson mergeSettings(List<SettingsJson> sources) {
  if (sources.isEmpty) return const SettingsJson();
  if (sources.length == 1) return sources.first;

  // Model: first non-null wins
  String? model;
  for (final s in sources) {
    if (s.model != null) {
      model = s.model;
      break;
    }
  }

  // Permissions: concatenate all rules
  final allAllow = <String>[];
  final allDeny = <String>[];
  final allAsk = <String>[];
  final allAdditionalDirs = <String>[];
  String? defaultMode;
  bool? disableBypass;

  for (final s in sources) {
    allAllow.addAll(s.permissions.allow);
    allDeny.addAll(s.permissions.deny);
    allAsk.addAll(s.permissions.ask);
    allAdditionalDirs.addAll(s.permissions.additionalDirectories);
    defaultMode ??= s.permissions.defaultMode;
    disableBypass ??= s.permissions.disableBypassPermissionsMode;
  }

  // Sandbox: first non-default wins
  SandboxSettings sandbox = const SandboxSettings();
  for (final s in sources) {
    if (s.sandbox.enabled) {
      sandbox = s.sandbox;
      break;
    }
  }

  // Environment variables: merge (earlier takes priority)
  final envVars = <String, String>{};
  for (final s in sources.reversed) {
    envVars.addAll(s.environmentVariables);
  }

  // Model overrides: merge
  final modelOverrides = <String, String>{};
  for (final s in sources.reversed) {
    modelOverrides.addAll(s.modelOverrides);
  }

  // Available models: first non-empty wins
  List<String> availableModels = [];
  for (final s in sources) {
    if (s.availableModels.isNotEmpty) {
      availableModels = s.availableModels;
      break;
    }
  }

  // Managed-only: any source can enable
  final managedOnly = sources.any((s) => s.allowManagedPermissionRulesOnly);

  return SettingsJson(
    model: model,
    permissions: PermissionSettings(
      allow: allAllow,
      deny: allDeny,
      ask: allAsk,
      defaultMode: defaultMode,
      disableBypassPermissionsMode: disableBypass,
      additionalDirectories: allAdditionalDirs,
    ),
    sandbox: sandbox,
    hooks: sources
        .firstWhere((s) => s.hooks != null, orElse: () => const SettingsJson())
        .hooks,
    installedPlugins: sources
        .expand((s) => s.installedPlugins)
        .toSet()
        .toList(),
    environmentVariables: envVars,
    modelOverrides: modelOverrides,
    availableModels: availableModels,
    allowManagedPermissionRulesOnly: managedOnly,
    syntaxHighlightingEnabled: sources.first.syntaxHighlightingEnabled,
    theme: sources
        .map((s) => s.theme)
        .firstWhere((t) => t != null, orElse: () => null),
    outputStyle: sources
        .map((s) => s.outputStyle)
        .firstWhere((o) => o != null, orElse: () => null),
  );
}

// ── Settings Writing ──

/// Write settings to a file (preserves unknown fields).
Future<void> writeSettingsFile(String path, SettingsJson settings) async {
  final file = File(path);
  await file.parent.create(recursive: true);

  // Merge with existing raw to preserve unknown fields
  final existing = await loadSettingsFile(path);
  final merged = <String, dynamic>{...?existing?.raw, ...settings.toJson()};

  final encoder = const JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(merged)}\n');
}

// ── Settings Change Detection ──

/// Detect changes between two settings.
class SettingsChange {
  final String field;
  final dynamic oldValue;
  final dynamic newValue;

  const SettingsChange({
    required this.field,
    required this.oldValue,
    required this.newValue,
  });

  @override
  String toString() => 'SettingsChange($field: $oldValue → $newValue)';
}

/// Detect changes between old and new settings.
List<SettingsChange> detectChanges(
  SettingsJson oldSettings,
  SettingsJson newSettings,
) {
  final changes = <SettingsChange>[];

  if (oldSettings.model != newSettings.model) {
    changes.add(
      SettingsChange(
        field: 'model',
        oldValue: oldSettings.model,
        newValue: newSettings.model,
      ),
    );
  }

  // Permission changes
  if (!_listEquals(
    oldSettings.permissions.allow,
    newSettings.permissions.allow,
  )) {
    changes.add(
      SettingsChange(
        field: 'permissions.allow',
        oldValue: oldSettings.permissions.allow,
        newValue: newSettings.permissions.allow,
      ),
    );
  }
  if (!_listEquals(
    oldSettings.permissions.deny,
    newSettings.permissions.deny,
  )) {
    changes.add(
      SettingsChange(
        field: 'permissions.deny',
        oldValue: oldSettings.permissions.deny,
        newValue: newSettings.permissions.deny,
      ),
    );
  }

  if (oldSettings.sandbox.enabled != newSettings.sandbox.enabled) {
    changes.add(
      SettingsChange(
        field: 'sandbox.enabled',
        oldValue: oldSettings.sandbox.enabled,
        newValue: newSettings.sandbox.enabled,
      ),
    );
  }

  if (oldSettings.theme != newSettings.theme) {
    changes.add(
      SettingsChange(
        field: 'theme',
        oldValue: oldSettings.theme,
        newValue: newSettings.theme,
      ),
    );
  }

  return changes;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ── Settings Paths ──

/// Get standard settings file paths.
class SettingsPaths {
  final String projectDir;
  final String configDir;

  const SettingsPaths({required this.projectDir, required this.configDir});

  String get projectSettings => '$projectDir/.neomage/settings.json';
  String get localSettings => '$projectDir/.neomage/settings.local.json';
  String get userSettings => '$configDir/settings.json';
  String get mcpConfig => '$configDir/.mcp.json';
  String get projectMcpConfig => '$projectDir/.mcp.json';
  String get keybindings => '$configDir/keybindings.json';
  String get credentials => '$configDir/credentials.json';
}
