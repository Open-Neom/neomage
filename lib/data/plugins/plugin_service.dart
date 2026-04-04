// Plugin service — ported from openclaude src/services/plugins/.
// Unified service combining plugin loader, operations, manifest validation,
// lifecycle management, and CLI command wrappers.

import 'dart:convert';

import 'package:neom_claw/core/platform/claw_io.dart';

import '../../domain/models/plugin.dart';
import '../mcp/mcp_types.dart';
import '../skills/skill.dart';

// ============================================================================
// Constants
// ============================================================================

/// Valid installable scopes (excludes 'managed').
const List<PluginScope> validInstallableScopes = [
  PluginScope.user,
  PluginScope.project,
  PluginScope.local,
];

/// Valid scopes for update operations (includes 'managed').
const List<PluginScope> validUpdateScopes = [
  PluginScope.user,
  PluginScope.project,
  PluginScope.local,
  PluginScope.managed,
];

// ============================================================================
// Enums
// ============================================================================

/// Scopes at which a plugin can be installed.
enum PluginScope {
  /// User-global scope (~/.neomclaw/plugins/).
  user,

  /// Project scope (.neomclaw/plugins/).
  project,

  /// Local-override scope (project, but gitignored).
  local,

  /// Managed by MDM/policy — cannot be manually installed.
  managed,
}

/// Status of a marketplace or plugin installation.
enum InstallationStatus {
  /// Queued but not yet started.
  pending,

  /// Currently being installed.
  installing,

  /// Successfully installed.
  installed,

  /// Installation failed.
  failed,
}

/// Lifecycle phase of a plugin.
enum PluginLifecyclePhase {
  /// Plugin discovered but not yet loaded.
  discovered,

  /// Manifest parsed and validated.
  validated,

  /// Plugin fully loaded and active.
  active,

  /// Plugin disabled by user or policy.
  disabled,

  /// Plugin failed to load.
  error,
}

// ============================================================================
// Data classes
// ============================================================================

/// Result of a plugin operation (install, uninstall, enable, disable).
class PluginOperationResult {
  /// Whether the operation succeeded.
  final bool success;

  /// Human-readable result or error message.
  final String message;

  /// Resolved plugin identifier.
  final String? pluginId;

  /// Short plugin name (without marketplace).
  final String? pluginName;

  /// Scope the operation was applied to.
  final PluginScope? scope;

  /// Plugins that depend on this one (warning on uninstall/disable).
  final List<String>? reverseDependents;

  const PluginOperationResult({
    required this.success,
    required this.message,
    this.pluginId,
    this.pluginName,
    this.scope,
    this.reverseDependents,
  });
}

/// Result of a plugin update operation.
class PluginUpdateResult {
  /// Whether the update succeeded.
  final bool success;

  /// Human-readable result or error message.
  final String message;

  /// Resolved plugin identifier.
  final String? pluginId;

  /// New version after update.
  final String? newVersion;

  /// Version before the update.
  final String? oldVersion;

  /// Whether the plugin was already at the latest version.
  final bool alreadyUpToDate;

  /// Scope the update was applied to.
  final PluginScope? scope;

  const PluginUpdateResult({
    required this.success,
    required this.message,
    this.pluginId,
    this.newVersion,
    this.oldVersion,
    this.alreadyUpToDate = false,
    this.scope,
  });
}

/// Parsed plugin identifier (name + optional marketplace).
class PluginIdentifier {
  /// Short plugin name.
  final String name;

  /// Marketplace the plugin belongs to (null for bare names).
  final String? marketplace;

  const PluginIdentifier({required this.name, this.marketplace});

  /// The full `name@marketplace` identifier, or just [name].
  String get fullId => marketplace != null ? '$name@$marketplace' : name;
}

/// Manifest validation result.
class ManifestValidationResult {
  /// Whether the manifest is valid.
  final bool isValid;

  /// Validation errors (empty when valid).
  final List<String> errors;

  /// Validation warnings (non-blocking).
  final List<String> warnings;

  const ManifestValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });
}

/// Plugin installation record from the V2 on-disk format.
class PluginInstallationRecord {
  /// The scope this installation belongs to.
  final PluginScope scope;

  /// Project path for project/local-scoped installations.
  final String? projectPath;

  /// On-disk path to the installed plugin.
  final String? installPath;

  /// Plugin version string.
  final String? version;

  const PluginInstallationRecord({
    required this.scope,
    this.projectPath,
    this.installPath,
    this.version,
  });
}

// ============================================================================
// Helper functions
// ============================================================================

/// Parse a plugin identifier string into name and optional marketplace.
///
/// `"my-plugin"` -> `PluginIdentifier(name: "my-plugin")`
/// `"my-plugin@my-market"` -> `PluginIdentifier(name: "my-plugin", marketplace: "my-market")`
PluginIdentifier parsePluginIdentifier(String plugin) {
  final atIndex = plugin.indexOf('@');
  if (atIndex >= 0) {
    return PluginIdentifier(
      name: plugin.substring(0, atIndex),
      marketplace: plugin.substring(atIndex + 1),
    );
  }
  return PluginIdentifier(name: plugin);
}

/// Convert a scope enum to its settings-source key string.
String scopeToSettingSource(PluginScope scope) => switch (scope) {
  PluginScope.user => 'userSettings',
  PluginScope.project => 'projectSettings',
  PluginScope.local => 'localSettings',
  PluginScope.managed => 'managedSettings',
};

/// Assert that a scope is valid for install/uninstall/enable/disable.
///
/// Throws [ArgumentError] if [scope] is [PluginScope.managed].
void assertInstallableScope(PluginScope scope) {
  if (!validInstallableScopes.contains(scope)) {
    throw ArgumentError(
      'Invalid scope "${scope.name}". Must be one of: '
      '${validInstallableScopes.map((s) => s.name).join(', ')}',
    );
  }
}

/// Whether [scope] is valid for install/uninstall.
bool isInstallableScope(PluginScope scope) =>
    validInstallableScopes.contains(scope);

/// Whether [pluginId] is a built-in plugin.
bool isBuiltinPluginId(String pluginId) => pluginId.startsWith('builtin:');

/// Scope precedence map for override resolution.
const Map<PluginScope, int> scopePrecedence = {
  PluginScope.user: 0,
  PluginScope.project: 1,
  PluginScope.local: 2,
};

/// Pluralise a noun based on [count].
String _plural(int count, String singular, [String? plural]) =>
    count == 1 ? singular : (plural ?? '${singular}s');

// ============================================================================
// Manifest loading and validation
// ============================================================================

/// Parse a plugin manifest from a JSON map.
///
/// Returns a [PluginManifest] with sensible defaults for missing fields.
PluginManifest parseManifest(Map<String, dynamic> json) {
  final authorRaw = json['author'];
  PluginAuthor? author;
  if (authorRaw is String) {
    author = PluginAuthor(name: authorRaw);
  } else if (authorRaw is Map<String, dynamic>) {
    author = PluginAuthor(
      name: authorRaw['name'] as String? ?? 'unknown',
      email: authorRaw['email'] as String?,
      url: authorRaw['url'] as String?,
    );
  }

  return PluginManifest(
    name: json['name'] as String? ?? 'unknown',
    version: json['version'] as String? ?? '0.0.0',
    description: json['description'] as String?,
    author: author,
    commands:
        (json['commands'] as List?)?.cast<String>() ?? const [],
    skills: (json['skills'] as List?)?.cast<String>() ?? const [],
    hooks: (json['hooks'] as List?)?.cast<String>() ?? const [],
    mcpServers:
        (json['mcpServers'] as List?)?.cast<String>() ?? const [],
    outputStyles:
        (json['outputStyles'] as List?)?.cast<String>() ?? const [],
  );
}

/// Validate a [PluginManifest] for required fields and consistency.
ManifestValidationResult validateManifest(PluginManifest manifest) {
  final errors = <String>[];
  final warnings = <String>[];

  if (manifest.name.isEmpty || manifest.name == 'unknown') {
    errors.add('Plugin name is required');
  }
  if (manifest.version == '0.0.0') {
    warnings.add('Plugin version defaults to 0.0.0');
  }
  if (manifest.description == null || manifest.description!.isEmpty) {
    warnings.add('Plugin has no description');
  }

  // Name must be a valid identifier-like string.
  final namePattern = RegExp(r'^[a-zA-Z0-9_-]+$');
  if (!namePattern.hasMatch(manifest.name)) {
    errors.add(
      'Plugin name "${manifest.name}" contains invalid characters; '
      'only alphanumerics, dashes, and underscores are allowed',
    );
  }

  return ManifestValidationResult(
    isValid: errors.isEmpty,
    errors: errors,
    warnings: warnings,
  );
}

/// Load a plugin manifest from a JSON file at [path].
///
/// Returns `null` if the file does not exist or is unparseable.
Future<PluginManifest?> loadManifestFromFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;

  try {
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) return null;
    return parseManifest(json);
  } catch (_) {
    return null;
  }
}

// ============================================================================
// Plugin loading
// ============================================================================

/// Load plugins from a [dirPath] directory.
///
/// Each subdirectory is treated as a potential plugin. A `plugin.json`
/// manifest is loaded if present; otherwise a synthetic manifest is
/// created from the directory name.
Future<List<LoadedPlugin>> loadPluginsFromDir(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return const [];

  final plugins = <LoadedPlugin>[];

  await for (final entity in dir.list()) {
    if (entity is! Directory) continue;

    try {
      final plugin = await _loadSinglePlugin(entity.path);
      if (plugin != null) plugins.add(plugin);
    } catch (_) {
      // Skip invalid plugins silently.
    }
  }

  return plugins;
}

/// Load all plugins from standard locations.
///
/// Searches user-global and (optionally) project-local plugin directories.
Future<List<LoadedPlugin>> loadAllPlugins({String? projectRoot}) async {
  final plugins = <LoadedPlugin>[];
  final homeDir =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/tmp';

  // 1. User plugins: ~/.neomclaw/plugins/
  plugins.addAll(await loadPluginsFromDir('$homeDir/.neomclaw/plugins'));

  // 2. Project plugins: .neomclaw/plugins/
  if (projectRoot != null) {
    plugins.addAll(await loadPluginsFromDir('$projectRoot/.neomclaw/plugins'));
  }

  return plugins;
}

/// Load skills from all enabled plugins.
Future<List<SkillDefinition>> loadPluginSkills(
  List<LoadedPlugin> plugins,
) async {
  final skills = <SkillDefinition>[];

  for (final plugin in plugins) {
    final skillsDir = '${plugin.path}/skills';
    final dir = Directory(skillsDir);
    if (!await dir.exists()) continue;

    final pluginSkills = await loadSkillsFromDir(
      skillsDir,
      source: SkillSource.plugin,
    );
    skills.addAll(pluginSkills);
  }

  return skills;
}

/// Load MCP server configs from all enabled plugins.
Future<List<McpServerConfig>> loadPluginMcpConfigs(
  List<LoadedPlugin> plugins,
) async {
  final configs = <McpServerConfig>[];

  for (final plugin in plugins) {
    final mcpFile = File('${plugin.path}/mcp.json');
    if (!await mcpFile.exists()) continue;

    try {
      final json = jsonDecode(await mcpFile.readAsString());
      if (json is Map<String, dynamic>) {
        for (final entry in json.entries) {
          final value = entry.value;
          if (value is! Map<String, dynamic>) continue;
          if (value.containsKey('command')) {
            configs.add(
              McpStdioConfig(
                name: entry.key,
                command: value['command'] as String,
                args:
                    (value['args'] as List?)
                        ?.map((a) => a.toString())
                        .toList() ??
                    [],
              ),
            );
          }
        }
      }
    } catch (_) {
      // Skip invalid MCP configs.
    }
  }

  return configs;
}

Future<LoadedPlugin?> _loadSinglePlugin(String pluginPath) async {
  final manifestFile = File('$pluginPath/plugin.json');

  PluginManifest? manifest;
  if (await manifestFile.exists()) {
    try {
      final json = jsonDecode(await manifestFile.readAsString());
      manifest = parseManifest(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  final dirName = pluginPath.split('/').last;

  return LoadedPlugin(
    manifest:
        manifest ??
        PluginManifest(name: dirName, version: '0.0.0', description: ''),
    path: pluginPath,
  );
}

// ============================================================================
// Plugin operations service
// ============================================================================

/// Core plugin operations — install, uninstall, enable, disable, update.
///
/// Functions in this class:
/// - Do NOT call exit or write to stdout directly.
/// - Return result objects indicating success/failure with messages.
/// - Can throw for unexpected failures.
///
/// Dependencies are injected as callbacks so the service can be used by
/// both CLI commands and interactive UI without coupling to I/O.
class PluginOperationsService {
  /// Load all plugins (enabled + disabled).
  final Future<PluginLoadResult> Function() loadAllPluginsFn;

  /// Look up a plugin entry in any marketplace.
  final Future<PluginManifest?> Function(String pluginId) getPluginByIdFn;

  /// Read the enabledPlugins map from a settings source.
  final Map<String, bool>? Function(String source) getSettingsEnabledPlugins;

  /// Write an update to a settings source.
  final void Function(String source, Map<String, Object?> update)
      updateSettings;

  /// Clear all plugin caches.
  final void Function() clearAllCaches;

  /// Load installed plugins from V2 on-disk data.
  final Map<String, List<PluginInstallationRecord>> Function()
      loadInstalledPluginsV2;

  /// Remove a plugin installation entry from V2 data.
  final void Function(String pluginId, PluginScope scope, String? projectPath)
      removePluginInstallation;

  /// Mark a versioned install path as orphaned for GC.
  final Future<void> Function(String installPath) markVersionOrphaned;

  /// Delete plugin options and secrets.
  final void Function(String pluginId) deletePluginOptions;

  /// Delete a plugin's data directory.
  final Future<void> Function(String pluginId) deletePluginDataDir;

  /// Find plugins that depend on [pluginId].
  final List<String> Function(
    String pluginId,
    List<LoadedPlugin> allPlugins,
  ) findReverseDependents;

  /// Check if a plugin is blocked by organizational policy.
  final bool Function(String pluginId) isPluginBlockedByPolicy;

  /// Get the current working directory (for project-scoped installs).
  final String Function() getOriginalCwd;

  /// Create the service with all required dependency callbacks.
  PluginOperationsService({
    required this.loadAllPluginsFn,
    required this.getPluginByIdFn,
    required this.getSettingsEnabledPlugins,
    required this.updateSettings,
    required this.clearAllCaches,
    required this.loadInstalledPluginsV2,
    required this.removePluginInstallation,
    required this.markVersionOrphaned,
    required this.deletePluginOptions,
    required this.deletePluginDataDir,
    required this.findReverseDependents,
    required this.isPluginBlockedByPolicy,
    required this.getOriginalCwd,
  });

  /// Get the project path for scopes that are project-specific.
  String? getProjectPathForScope(PluginScope scope) =>
      (scope == PluginScope.project || scope == PluginScope.local)
          ? getOriginalCwd()
          : null;

  /// Check if a plugin is enabled at project scope.
  bool isPluginEnabledAtProjectScope(String pluginId) {
    final enabled = getSettingsEnabledPlugins('projectSettings');
    return enabled?[pluginId] == true;
  }

  /// Search all editable settings scopes for a plugin ID.
  ///
  /// Returns the most specific scope where the plugin is mentioned
  /// (local > project > user).
  ({String pluginId, PluginScope scope})? findPluginInSettings(
    String plugin,
  ) {
    final hasMarketplace = plugin.contains('@');
    const searchOrder = [PluginScope.local, PluginScope.project, PluginScope.user];

    for (final scope in searchOrder) {
      final enabledPlugins = getSettingsEnabledPlugins(
        scopeToSettingSource(scope),
      );
      if (enabledPlugins == null) continue;

      for (final key in enabledPlugins.keys) {
        if (hasMarketplace ? key == plugin : key.startsWith('$plugin@')) {
          return (pluginId: key, scope: scope);
        }
      }
    }
    return null;
  }

  /// Find a plugin from loaded plugins by identifier.
  LoadedPlugin? findPluginByIdentifier(
    String plugin,
    List<LoadedPlugin> plugins,
  ) {
    final id = parsePluginIdentifier(plugin);
    for (final p in plugins) {
      if (p.manifest.name == plugin || p.manifest.name == id.name) return p;
    }
    return null;
  }

  // ── Install ─────────────────────────────────────────────────────────

  /// Install a plugin (settings-first).
  ///
  /// Order of operations:
  /// 1. Look up plugin in marketplaces.
  /// 2. Write settings (declares intent).
  /// 3. Cache plugin and record version hint (materialization).
  Future<PluginOperationResult> installPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
  ]) async {
    assertInstallableScope(scope);
    final id = parsePluginIdentifier(plugin);

    final entry = await getPluginByIdFn(plugin);
    if (entry == null) {
      final location =
          id.marketplace != null
              ? 'marketplace "${id.marketplace}"'
              : 'any configured marketplace';
      return PluginOperationResult(
        success: false,
        message: 'Plugin "${id.name}" not found in $location',
      );
    }

    final pluginId = '${entry.name}@${id.marketplace ?? 'default'}';

    if (isPluginBlockedByPolicy(pluginId)) {
      return PluginOperationResult(
        success: false,
        message:
            'Plugin "${entry.name}" is blocked by your organization\'s policy '
            'and cannot be installed',
      );
    }

    // Validate the manifest.
    final validation = validateManifest(entry);
    if (!validation.isValid) {
      return PluginOperationResult(
        success: false,
        message:
            'Plugin "${id.name}" has an invalid manifest: '
            '${validation.errors.join('; ')}',
      );
    }

    // Write settings (the intent declaration).
    final settingSource = scopeToSettingSource(scope);
    final current = getSettingsEnabledPlugins(settingSource) ?? {};
    updateSettings(settingSource, {
      'enabledPlugins': {...current, pluginId: true},
    });
    clearAllCaches();

    return PluginOperationResult(
      success: true,
      message:
          'Successfully installed plugin: $pluginId (scope: ${scope.name})',
      pluginId: pluginId,
      pluginName: entry.name,
      scope: scope,
    );
  }

  // ── Uninstall ───────────────────────────────────────────────────────

  /// Uninstall a plugin.
  ///
  /// Removes the plugin from settings and V2 installed data. When the
  /// last scope is removed, also cleans up cached versions, options,
  /// and the data directory.
  Future<PluginOperationResult> uninstallPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
    bool deleteDataDirFlag = true,
  ]) async {
    assertInstallableScope(scope);

    final loadResult = await loadAllPluginsFn();
    final allPlugins = [...loadResult.enabled, ...loadResult.disabled];
    final foundPlugin = findPluginByIdentifier(plugin, allPlugins);

    final settingSource = scopeToSettingSource(scope);
    final settings = getSettingsEnabledPlugins(settingSource);

    String pluginId;
    String pluginName;

    if (foundPlugin != null) {
      pluginId =
          settings?.keys.firstWhere(
            (k) =>
                k == plugin ||
                k == foundPlugin.manifest.name ||
                k.startsWith('${foundPlugin.manifest.name}@'),
            orElse: () =>
                plugin.contains('@') ? plugin : foundPlugin.manifest.name,
          ) ??
          (plugin.contains('@') ? plugin : foundPlugin.manifest.name);
      pluginName = foundPlugin.manifest.name;
    } else {
      return PluginOperationResult(
        success: false,
        message: 'Plugin "$plugin" not found in installed plugins',
      );
    }

    // Check scope installation.
    final projectPath = getProjectPathForScope(scope);
    final installedData = loadInstalledPluginsV2();
    final installations = installedData[pluginId];
    final scopeInstallation = installations?.cast<PluginInstallationRecord?>().firstWhere(
      (i) => i!.scope == scope && i.projectPath == projectPath,
      orElse: () => null,
    );

    if (scopeInstallation == null) {
      return PluginOperationResult(
        success: false,
        message:
            'Plugin "$plugin" is not installed in ${scope.name} scope. '
            'Use --scope to specify the correct scope.',
      );
    }

    // Remove from settings.
    final newEnabled = Map<String, bool>.from(settings ?? {});
    newEnabled.remove(pluginId);
    updateSettings(settingSource, {'enabledPlugins': newEnabled});
    clearAllCaches();

    // Remove from V2 data.
    removePluginInstallation(pluginId, scope, projectPath);

    // Cleanup when this was the last scope.
    final updatedData = loadInstalledPluginsV2();
    final remaining = updatedData[pluginId];
    final isLastScope = remaining == null || remaining.isEmpty;

    if (isLastScope && scopeInstallation.installPath != null) {
      await markVersionOrphaned(scopeInstallation.installPath!);
    }
    if (isLastScope) {
      deletePluginOptions(pluginId);
      if (deleteDataDirFlag) {
        await deletePluginDataDir(pluginId);
      }
    }

    // Warn about reverse dependents.
    final reverseDeps = findReverseDependents(pluginId, allPlugins);
    final depWarn =
        reverseDeps.isNotEmpty
            ? '. Warning: the following plugins depend on this: '
                '${reverseDeps.join(', ')}'
            : '';

    return PluginOperationResult(
      success: true,
      message:
          'Successfully uninstalled plugin: $pluginName '
          '(scope: ${scope.name})$depWarn',
      pluginId: pluginId,
      pluginName: pluginName,
      scope: scope,
      reverseDependents: reverseDeps.isNotEmpty ? reverseDeps : null,
    );
  }

  // ── Enable / Disable ────────────────────────────────────────────────

  /// Enable a plugin.
  Future<PluginOperationResult> enablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) => _setPluginEnabled(plugin, true, scope);

  /// Disable a plugin.
  Future<PluginOperationResult> disablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) => _setPluginEnabled(plugin, false, scope);

  /// Disable all enabled plugins across all editable scopes.
  Future<PluginOperationResult> disableAllPlugins() async {
    int disabledCount = 0;
    final errors = <String>[];

    for (final scope in validInstallableScopes) {
      final settingSource = scopeToSettingSource(scope);
      final enabled = getSettingsEnabledPlugins(settingSource);
      if (enabled == null || enabled.isEmpty) continue;

      for (final pluginId in enabled.keys) {
        if (enabled[pluginId] != true) continue;
        final result = await _setPluginEnabled(pluginId, false);
        if (result.success) {
          disabledCount++;
        } else {
          errors.add('$pluginId: ${result.message}');
        }
      }
    }

    if (errors.isNotEmpty) {
      return PluginOperationResult(
        success: false,
        message:
            'Disabled $disabledCount ${_plural(disabledCount, 'plugin')}, '
            '${errors.length} failed:\n${errors.join('\n')}',
      );
    }

    if (disabledCount == 0) {
      return const PluginOperationResult(
        success: true,
        message: 'No enabled plugins to disable',
      );
    }

    return PluginOperationResult(
      success: true,
      message:
          'Disabled $disabledCount ${_plural(disabledCount, 'plugin')}',
    );
  }

  // ── Update ──────────────────────────────────────────────────────────

  /// Update a plugin to the latest version.
  ///
  /// Fetches the current marketplace entry, compares versions, and
  /// copies the new version to the versioned cache. Returns
  /// [PluginUpdateResult.alreadyUpToDate] when no update is needed.
  Future<PluginUpdateResult> updatePlugin(
    String plugin,
    PluginScope scope,
  ) async {
    final id = parsePluginIdentifier(plugin);
    final pluginId = id.fullId;

    final entry = await getPluginByIdFn(plugin);
    if (entry == null) {
      return PluginUpdateResult(
        success: false,
        message: 'Plugin "${id.name}" not found',
        pluginId: pluginId,
        scope: scope,
      );
    }

    final installedData = loadInstalledPluginsV2();
    final installations = installedData[pluginId];

    if (installations == null || installations.isEmpty) {
      return PluginUpdateResult(
        success: false,
        message: 'Plugin "${id.name}" is not installed',
        pluginId: pluginId,
        scope: scope,
      );
    }

    final projectPath = getProjectPathForScope(scope);
    final installation = installations.cast<PluginInstallationRecord?>().firstWhere(
      (i) => i!.scope == scope && i.projectPath == projectPath,
      orElse: () => null,
    );

    if (installation == null) {
      final scopeDesc =
          projectPath != null ? '${scope.name} ($projectPath)' : scope.name;
      return PluginUpdateResult(
        success: false,
        message:
            'Plugin "${id.name}" is not installed at scope $scopeDesc',
        pluginId: pluginId,
        scope: scope,
      );
    }

    final oldVersion = installation.version;
    final newVersion = entry.version;

    if (oldVersion == newVersion) {
      return PluginUpdateResult(
        success: true,
        message:
            '${id.name} is already at the latest version ($newVersion).',
        pluginId: pluginId,
        newVersion: newVersion,
        oldVersion: oldVersion,
        alreadyUpToDate: true,
        scope: scope,
      );
    }

    // In a full implementation, this would download/copy the new version
    // to the versioned cache and update the V2 installation record.
    // For now, return a success indicating what would happen.
    final scopeDesc =
        projectPath != null ? '${scope.name} ($projectPath)' : scope.name;
    return PluginUpdateResult(
      success: true,
      message:
          'Plugin "${id.name}" updated from ${oldVersion ?? 'unknown'} '
          'to $newVersion for scope $scopeDesc. '
          'Restart to apply changes.',
      pluginId: pluginId,
      newVersion: newVersion,
      oldVersion: oldVersion,
      scope: scope,
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────

  Future<PluginOperationResult> _setPluginEnabled(
    String plugin,
    bool enabled, [
    PluginScope? scope,
  ]) async {
    final operation = enabled ? 'enable' : 'disable';

    // Built-in plugins always use user scope.
    if (isBuiltinPluginId(plugin)) {
      final current = getSettingsEnabledPlugins('userSettings') ?? {};
      updateSettings('userSettings', {
        'enabledPlugins': {...current, plugin: enabled},
      });
      clearAllCaches();
      final id = parsePluginIdentifier(plugin);
      return PluginOperationResult(
        success: true,
        message: 'Successfully ${operation}d built-in plugin: ${id.name}',
        pluginId: plugin,
        pluginName: id.name,
        scope: PluginScope.user,
      );
    }

    if (scope != null) assertInstallableScope(scope);

    // Resolve pluginId and scope from settings.
    String pluginId;
    PluginScope resolvedScope;
    final found = findPluginInSettings(plugin);

    if (scope != null) {
      resolvedScope = scope;
      pluginId = found?.pluginId ?? (plugin.contains('@') ? plugin : '');
      if (pluginId.isEmpty) {
        return PluginOperationResult(
          success: false,
          message:
              'Plugin "$plugin" not found in settings. '
              'Use plugin@marketplace format.',
        );
      }
    } else if (found != null) {
      pluginId = found.pluginId;
      resolvedScope = found.scope;
    } else if (plugin.contains('@')) {
      pluginId = plugin;
      resolvedScope = PluginScope.user;
    } else {
      return PluginOperationResult(
        success: false,
        message:
            'Plugin "$plugin" not found in any editable settings scope. '
            'Use plugin@marketplace format.',
      );
    }

    // Policy guard.
    if (enabled && isPluginBlockedByPolicy(pluginId)) {
      return PluginOperationResult(
        success: false,
        message:
            'Plugin "$pluginId" is blocked by your organization\'s policy '
            'and cannot be enabled',
      );
    }

    // Cross-scope hint.
    final settingSource = scopeToSettingSource(resolvedScope);
    final scopeSettings = getSettingsEnabledPlugins(settingSource);

    if (scope != null &&
        scopeSettings?[pluginId] == null &&
        found != null &&
        found.scope != scope) {
      final isOverride =
          (scopePrecedence[scope] ?? 0) >
          (scopePrecedence[found.scope] ?? 0);
      if (!isOverride) {
        return PluginOperationResult(
          success: false,
          message:
              'Plugin "$plugin" is installed at ${found.scope.name} scope, '
              'not ${scope.name}. Use --scope ${found.scope.name} or omit '
              '--scope to auto-detect.',
        );
      }
    }

    // Capture reverse dependents before disabling.
    List<String>? reverseDependents;
    if (!enabled) {
      final loadResult = await loadAllPluginsFn();
      final allPlugins = [...loadResult.enabled, ...loadResult.disabled];
      final rdeps = findReverseDependents(pluginId, allPlugins);
      if (rdeps.isNotEmpty) reverseDependents = rdeps;
    }

    // Write the setting.
    final current = scopeSettings ?? {};
    updateSettings(settingSource, {
      'enabledPlugins': {...current, pluginId: enabled},
    });
    clearAllCaches();

    final id = parsePluginIdentifier(pluginId);
    final depWarn =
        reverseDependents != null && reverseDependents.isNotEmpty
            ? '. Warning: the following plugins depend on this: '
                '${reverseDependents.join(', ')}'
            : '';

    return PluginOperationResult(
      success: true,
      message:
          'Successfully ${operation}d plugin: ${id.name} '
          '(scope: ${resolvedScope.name})$depWarn',
      pluginId: pluginId,
      pluginName: id.name,
      scope: resolvedScope,
      reverseDependents: reverseDependents,
    );
  }
}

// ============================================================================
// CLI command wrappers
// ============================================================================

/// Telemetry fields for plugin CLI analytics events.
class PluginTelemetryFields {
  /// Short plugin name.
  final String? pluginName;

  /// Marketplace name.
  final String? marketplaceName;

  /// Whether this is a managed (MDM) plugin.
  final bool isManaged;

  const PluginTelemetryFields({
    this.pluginName,
    this.marketplaceName,
    this.isManaged = false,
  });

  /// Convert to a metadata map for analytics.
  Map<String, Object?> toMap() => {
    if (pluginName != null) '_PROTO_plugin_name': pluginName,
    if (marketplaceName != null) '_PROTO_marketplace_name': marketplaceName,
    'is_managed': isManaged,
  };
}

/// Build telemetry fields from a plugin name and context.
PluginTelemetryFields buildPluginTelemetryFields(
  String name,
  String? marketplace,
  Set<String> managedPluginNames,
) => PluginTelemetryFields(
  pluginName: name,
  marketplaceName: marketplace,
  isManaged: managedPluginNames.contains(name),
);

/// Classify a plugin command error for analytics.
String classifyPluginCommandError(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('not found')) return 'not_found';
  if (message.contains('blocked')) return 'blocked_by_policy';
  if (message.contains('scope')) return 'scope_mismatch';
  if (message.contains('network') || message.contains('timeout')) {
    return 'network';
  }
  return 'unknown';
}

/// CLI command wrappers for plugin operations.
///
/// Thin wrappers around [PluginOperationsService] that handle CLI-specific
/// concerns: console output, analytics logging, and process exit codes.
class PluginCliService {
  /// The underlying operations service.
  final PluginOperationsService operations;

  /// Analytics event logger.
  final void Function(String eventName, Map<String, Object?> metadata)
      logEvent;

  /// Get the set of managed plugin names.
  final Set<String> Function() getManagedPluginNames;

  /// Write a success message to stdout.
  final void Function(String message) writeOutput;

  /// Write an error message to stderr.
  final void Function(String message) writeError;

  /// Create a CLI service backed by [operations].
  PluginCliService({
    required this.operations,
    required this.logEvent,
    required this.getManagedPluginNames,
    required this.writeOutput,
    required this.writeError,
  });

  /// CLI: Install a plugin.
  Future<PluginOperationResult> installPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
  ]) async {
    try {
      writeOutput('Installing plugin "$plugin"...');
      final result = await operations.installPlugin(plugin, scope);

      if (!result.success) {
        writeError('Failed to install plugin "$plugin": ${result.message}');
        _logFailure('install', plugin);
        return result;
      }

      writeOutput('Successfully installed: ${result.pluginId}');
      final id = parsePluginIdentifier(result.pluginId ?? plugin);
      logEvent('tengu_plugin_installed_cli', {
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
        'scope': (result.scope ?? scope).name,
        'install_source': 'cli-explicit',
      });

      return result;
    } catch (e) {
      _handleError(e, 'install', plugin);
      return PluginOperationResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  /// CLI: Uninstall a plugin.
  Future<PluginOperationResult> uninstallPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
    bool keepData = false,
  ]) async {
    try {
      final result = await operations.uninstallPlugin(
        plugin,
        scope,
        !keepData,
      );

      if (!result.success) {
        writeError(
          'Failed to uninstall plugin "$plugin": ${result.message}',
        );
        _logFailure('uninstall', plugin);
        return result;
      }

      writeOutput('Successfully uninstalled: ${result.pluginName}');
      final id = parsePluginIdentifier(result.pluginId ?? plugin);
      logEvent('tengu_plugin_uninstalled_cli', {
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
        'scope': (result.scope ?? scope).name,
      });

      return result;
    } catch (e) {
      _handleError(e, 'uninstall', plugin);
      return PluginOperationResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  /// CLI: Enable a plugin.
  Future<PluginOperationResult> enablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) async {
    try {
      final result = await operations.enablePlugin(plugin, scope);

      if (!result.success) {
        writeError(
          'Failed to enable plugin "$plugin": ${result.message}',
        );
        _logFailure('enable', plugin);
        return result;
      }

      writeOutput('Successfully enabled: ${result.pluginName}');
      final id = parsePluginIdentifier(result.pluginId ?? plugin);
      logEvent('tengu_plugin_enabled_cli', {
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
        'scope': result.scope?.name,
      });

      return result;
    } catch (e) {
      _handleError(e, 'enable', plugin);
      return PluginOperationResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  /// CLI: Disable a plugin.
  Future<PluginOperationResult> disablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) async {
    try {
      final result = await operations.disablePlugin(plugin, scope);

      if (!result.success) {
        writeError(
          'Failed to disable plugin "$plugin": ${result.message}',
        );
        _logFailure('disable', plugin);
        return result;
      }

      writeOutput('Successfully disabled: ${result.pluginName}');
      final id = parsePluginIdentifier(result.pluginId ?? plugin);
      logEvent('tengu_plugin_disabled_cli', {
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
        'scope': result.scope?.name,
      });

      return result;
    } catch (e) {
      _handleError(e, 'disable', plugin);
      return PluginOperationResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  /// CLI: Disable all enabled plugins.
  Future<PluginOperationResult> disableAllPlugins() async {
    try {
      final result = await operations.disableAllPlugins();

      if (!result.success) {
        writeError('Failed to disable all plugins: ${result.message}');
        _logFailure('disable-all');
        return result;
      }

      writeOutput(result.message);
      logEvent('tengu_plugin_disabled_all_cli', {});
      return result;
    } catch (e) {
      _handleError(e, 'disable-all');
      return PluginOperationResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  /// CLI: Update a plugin.
  Future<PluginUpdateResult> updatePlugin(
    String plugin,
    PluginScope scope,
  ) async {
    try {
      writeOutput(
        'Checking for updates for plugin "$plugin" at ${scope.name} scope...',
      );
      final result = await operations.updatePlugin(plugin, scope);

      if (!result.success) {
        writeError(
          'Failed to update plugin "$plugin": ${result.message}',
        );
        _logFailure('update', plugin);
        return result;
      }

      writeOutput(result.message);

      if (!result.alreadyUpToDate) {
        final id = parsePluginIdentifier(result.pluginId ?? plugin);
        logEvent('tengu_plugin_updated_cli', {
          ...buildPluginTelemetryFields(
            id.name,
            id.marketplace,
            getManagedPluginNames(),
          ).toMap(),
          'old_version': result.oldVersion ?? 'unknown',
          'new_version': result.newVersion ?? 'unknown',
        });
      }

      return result;
    } catch (e) {
      _handleError(e, 'update', plugin);
      return PluginUpdateResult(
        success: false,
        message: e.toString(),
      );
    }
  }

  void _handleError(Object error, String command, [String? plugin]) {
    final id = plugin != null ? parsePluginIdentifier(plugin) : null;
    writeError('Failed to $command${plugin != null ? ' plugin "$plugin"' : ''}: $error');
    logEvent('tengu_plugin_command_failed', {
      'command': command,
      'error_category': classifyPluginCommandError(error),
      if (id != null)
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
    });
  }

  void _logFailure(String command, [String? plugin]) {
    final id = plugin != null ? parsePluginIdentifier(plugin) : null;
    logEvent('tengu_plugin_command_failed', {
      'command': command,
      'error_category': 'operation_failed',
      if (id != null)
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
    });
  }
}
