// Plugin service — port of openneomclaw/src/services/plugins/.
// Handles plugin installation, uninstallation, enabling, disabling, updating,
// background marketplace reconciliation, CLI command wrappers, and
// installation status tracking.

import 'dart:async';

import 'package:sint/sint.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Scopes at which a plugin can be installed.
enum PluginScope {
  user,
  project,
  local,
  managed,
}

/// Valid installable scopes (excludes 'managed' which can only come from
/// managed-settings.json).
const validInstallableScopes = <PluginScope>[
  PluginScope.user,
  PluginScope.project,
  PluginScope.local,
];

/// Valid scopes for update operations (includes 'managed').
const validUpdateScopes = <PluginScope>[
  PluginScope.user,
  PluginScope.project,
  PluginScope.local,
  PluginScope.managed,
];

/// Status of a marketplace or plugin installation.
enum InstallationStatus {
  pending,
  installing,
  installed,
  failed,
}

// ═══════════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════════

/// A single marketplace installation status entry.
class MarketplaceInstallStatus {
  final String name;
  final InstallationStatus status;
  final String? error;

  const MarketplaceInstallStatus({
    required this.name,
    required this.status,
    this.error,
  });

  MarketplaceInstallStatus copyWith({
    String? name,
    InstallationStatus? status,
    String? error,
  }) =>
      MarketplaceInstallStatus(
        name: name ?? this.name,
        status: status ?? this.status,
        error: error ?? this.error,
      );
}

/// A single plugin installation status entry.
class PluginInstallStatus {
  final String name;
  final InstallationStatus status;
  final String? error;

  const PluginInstallStatus({
    required this.name,
    required this.status,
    this.error,
  });
}

/// Overall installation status.
class PluginInstallationStatus {
  final List<MarketplaceInstallStatus> marketplaces;
  final List<PluginInstallStatus> plugins;

  const PluginInstallationStatus({
    this.marketplaces = const [],
    this.plugins = const [],
  });

  PluginInstallationStatus copyWith({
    List<MarketplaceInstallStatus>? marketplaces,
    List<PluginInstallStatus>? plugins,
  }) =>
      PluginInstallationStatus(
        marketplaces: marketplaces ?? this.marketplaces,
        plugins: plugins ?? this.plugins,
      );
}

/// Result of a plugin operation (install, uninstall, enable, disable).
class PluginOperationResult {
  final bool success;
  final String message;
  final String? pluginId;
  final String? pluginName;
  final PluginScope? scope;
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
  final bool success;
  final String message;
  final String? pluginId;
  final String? newVersion;
  final String? oldVersion;
  final bool alreadyUpToDate;
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

/// Result of a marketplace reconciliation run.
class ReconciliationResult {
  final List<String> installed;
  final List<String> updated;
  final List<String> failed;
  final List<String> upToDate;

  const ReconciliationResult({
    this.installed = const [],
    this.updated = const [],
    this.failed = const [],
    this.upToDate = const [],
  });
}

/// A loaded plugin from the marketplace.
class LoadedPlugin {
  final String name;
  final String? source;
  final String? version;
  final bool enabled;
  final PluginScope? scope;
  final String? installPath;
  final List<String> dependencies;

  const LoadedPlugin({
    required this.name,
    this.source,
    this.version,
    this.enabled = true,
    this.scope,
    this.installPath,
    this.dependencies = const [],
  });
}

/// A marketplace plugin entry.
class PluginMarketplaceEntry {
  final String name;
  final String? description;
  final String? version;
  final String? sourceType;
  final String? sourcePath;
  final List<String> dependencies;

  const PluginMarketplaceEntry({
    required this.name,
    this.description,
    this.version,
    this.sourceType,
    this.sourcePath,
    this.dependencies = const [],
  });
}

/// Parsed plugin identifier.
class PluginIdentifier {
  final String name;
  final String? marketplace;

  const PluginIdentifier({required this.name, this.marketplace});
}

/// Plugin installation record in V2 format.
class PluginInstallationRecord {
  final PluginScope scope;
  final String? projectPath;
  final String? installPath;
  final String? version;

  const PluginInstallationRecord({
    required this.scope,
    this.projectPath,
    this.installPath,
    this.version,
  });
}

/// V2 installed plugins data.
class InstalledPluginsV2 {
  final Map<String, List<PluginInstallationRecord>> plugins;

  const InstalledPluginsV2({this.plugins = const {}});
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper functions
// ═══════════════════════════════════════════════════════════════════════════

/// Parse a plugin identifier string into name and optional marketplace.
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

/// Convert a scope to a settings source key.
String scopeToSettingSource(PluginScope scope) {
  switch (scope) {
    case PluginScope.user:
      return 'userSettings';
    case PluginScope.project:
      return 'projectSettings';
    case PluginScope.local:
      return 'localSettings';
    case PluginScope.managed:
      return 'managedSettings';
  }
}

/// Assert that a scope is a valid installable scope.
void assertInstallableScope(PluginScope scope) {
  if (!validInstallableScopes.contains(scope)) {
    throw ArgumentError(
      'Invalid scope "${scope.name}". Must be one of: '
      '${validInstallableScopes.map((s) => s.name).join(', ')}',
    );
  }
}

/// Type guard for installable scopes.
bool isInstallableScope(PluginScope scope) {
  return validInstallableScopes.contains(scope);
}

/// Check if a plugin ID is a built-in plugin.
bool isBuiltinPluginId(String pluginId) {
  return pluginId.startsWith('builtin:');
}

/// Scope precedence for override resolution.
const _scopePrecedence = <PluginScope, int>{
  PluginScope.user: 0,
  PluginScope.project: 1,
  PluginScope.local: 2,
};

// ═══════════════════════════════════════════════════════════════════════════
// Marketplace diff
// ═══════════════════════════════════════════════════════════════════════════

/// A marketplace whose source changed.
class MarketplaceSourceChange {
  final String name;
  final String oldSource;
  final String newSource;

  const MarketplaceSourceChange({
    required this.name,
    required this.oldSource,
    required this.newSource,
  });
}

/// Result of diffing declared vs materialised marketplaces.
class MarketplaceDiff {
  final List<String> missing;
  final List<MarketplaceSourceChange> sourceChanged;

  const MarketplaceDiff({
    this.missing = const [],
    this.sourceChanged = const [],
  });

  bool get isEmpty => missing.isEmpty && sourceChanged.isEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════
// Reconciliation progress
// ═══════════════════════════════════════════════════════════════════════════

/// Progress event during marketplace reconciliation.
abstract class ReconciliationProgressEvent {
  String get name;
}

class ReconciliationInstalling extends ReconciliationProgressEvent {
  @override
  final String name;
  ReconciliationInstalling(this.name);
}

class ReconciliationInstalled extends ReconciliationProgressEvent {
  @override
  final String name;
  ReconciliationInstalled(this.name);
}

class ReconciliationFailed extends ReconciliationProgressEvent {
  @override
  final String name;
  final String error;
  ReconciliationFailed(this.name, this.error);
}

// ═══════════════════════════════════════════════════════════════════════════
// Plugin operations service
// ═══════════════════════════════════════════════════════════════════════════

/// Core plugin operations — library functions that can be used by both
/// CLI commands and interactive UI.
///
/// Functions in this class:
/// - Do NOT call exit
/// - Do NOT write to console
/// - Return result objects indicating success/failure with messages
/// - Can throw errors for unexpected failures
class PluginOperationsService {
  final Future<List<LoadedPlugin>> Function() loadAllPlugins;
  final Future<PluginMarketplaceEntry?> Function(String) getPluginById;
  final Map<String, bool>? Function(String source) getSettingsEnabledPlugins;
  final void Function(String source, Map<String, Object?> update)
      updateSettings;
  final void Function() clearAllCaches;
  final InstalledPluginsV2 Function() loadInstalledPluginsV2;
  final void Function(String pluginId, PluginScope scope, String? projectPath)
      removePluginInstallation;
  final Future<void> Function(String installPath) markVersionOrphaned;
  final void Function(String pluginId) deletePluginOptions;
  final Future<void> Function(String pluginId) deletePluginDataDir;
  final List<String> Function(String pluginId, List<LoadedPlugin> allPlugins)
      findReverseDependents;
  final bool Function(String pluginId) isPluginBlockedByPolicy;
  final String Function() getOriginalCwd;
  final Set<String> Function() getManagedPluginNames;

  PluginOperationsService({
    required this.loadAllPlugins,
    required this.getPluginById,
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
    required this.getManagedPluginNames,
  });

  /// Get the project path for scopes that are project-specific.
  String? getProjectPathForScope(PluginScope scope) {
    return (scope == PluginScope.project || scope == PluginScope.local)
        ? getOriginalCwd()
        : null;
  }

  /// Check if a plugin is enabled at project scope in settings.
  bool isPluginEnabledAtProjectScope(String pluginId) {
    final enabled = getSettingsEnabledPlugins('projectSettings');
    return enabled?[pluginId] == true;
  }

  /// Search all editable settings scopes for a plugin ID.
  ({String pluginId, PluginScope scope})? findPluginInSettings(String plugin) {
    final hasMarketplace = plugin.contains('@');
    const searchOrder = [PluginScope.local, PluginScope.project, PluginScope.user];

    for (final scope in searchOrder) {
      final enabledPlugins = getSettingsEnabledPlugins(scopeToSettingSource(scope));
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
  LoadedPlugin? findPluginByIdentifier(String plugin, List<LoadedPlugin> plugins) {
    final id = parsePluginIdentifier(plugin);
    return plugins.cast<LoadedPlugin?>().firstWhere(
      (p) {
        if (p!.name == plugin || p.name == id.name) return true;
        if (id.marketplace != null && p.source != null) {
          return p.name == id.name && p.source!.contains('@${id.marketplace}');
        }
        return false;
      },
      orElse: () => null,
    );
  }

  /// Get the most relevant installation for a plugin from V2 data.
  ({PluginScope scope, String? projectPath}) getPluginInstallationFromV2(
    String pluginId,
  ) {
    final data = loadInstalledPluginsV2();
    final installations = data.plugins[pluginId];
    if (installations == null || installations.isEmpty) {
      return (scope: PluginScope.user, projectPath: null);
    }

    final currentProjectPath = getOriginalCwd();

    final localInstall = installations.cast<PluginInstallationRecord?>().firstWhere(
      (i) => i!.scope == PluginScope.local && i.projectPath == currentProjectPath,
      orElse: () => null,
    );
    if (localInstall != null) {
      return (scope: localInstall.scope, projectPath: localInstall.projectPath);
    }

    final projectInstall = installations.cast<PluginInstallationRecord?>().firstWhere(
      (i) => i!.scope == PluginScope.project && i.projectPath == currentProjectPath,
      orElse: () => null,
    );
    if (projectInstall != null) {
      return (scope: projectInstall.scope, projectPath: projectInstall.projectPath);
    }

    final userInstall = installations.cast<PluginInstallationRecord?>().firstWhere(
      (i) => i!.scope == PluginScope.user,
      orElse: () => null,
    );
    if (userInstall != null) {
      return (scope: userInstall.scope, projectPath: null);
    }

    return (
      scope: installations.first.scope,
      projectPath: installations.first.projectPath,
    );
  }

  /// Install a plugin (settings-first).
  Future<PluginOperationResult> installPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
  ]) async {
    assertInstallableScope(scope);
    final id = parsePluginIdentifier(plugin);

    final entry = await getPluginById(plugin);
    if (entry == null) {
      final location = id.marketplace != null
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

    // Write settings (the intent).
    final settingSource = scopeToSettingSource(scope);
    final current = getSettingsEnabledPlugins(settingSource) ?? {};
    updateSettings(settingSource, {
      'enabledPlugins': {...current, pluginId: true},
    });
    clearAllCaches();

    return PluginOperationResult(
      success: true,
      message: 'Successfully installed plugin: $pluginId (scope: ${scope.name})',
      pluginId: pluginId,
      pluginName: entry.name,
      scope: scope,
    );
  }

  /// Uninstall a plugin.
  Future<PluginOperationResult> uninstallPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
    bool deleteDataDirFlag = true,
  ]) async {
    assertInstallableScope(scope);

    final allPlugins = await loadAllPlugins();
    final foundPlugin = findPluginByIdentifier(plugin, allPlugins);

    final settingSource = scopeToSettingSource(scope);
    final settings = getSettingsEnabledPlugins(settingSource);

    String pluginId;
    String pluginName;

    if (foundPlugin != null) {
      pluginId = settings?.keys.firstWhere(
            (k) =>
                k == plugin ||
                k == foundPlugin.name ||
                k.startsWith('${foundPlugin.name}@'),
            orElse: () =>
                plugin.contains('@') ? plugin : foundPlugin.name,
          ) ??
          (plugin.contains('@') ? plugin : foundPlugin.name);
      pluginName = foundPlugin.name;
    } else {
      return PluginOperationResult(
        success: false,
        message: 'Plugin "$plugin" not found in installed plugins',
      );
    }

    // Check scope installation.
    final projectPath = getProjectPathForScope(scope);
    final installedData = loadInstalledPluginsV2();
    final installations = installedData.plugins[pluginId];
    final scopeInstallation = installations?.cast<PluginInstallationRecord?>().firstWhere(
      (i) => i!.scope == scope && i.projectPath == projectPath,
      orElse: () => null,
    );

    if (scopeInstallation == null) {
      final actual = getPluginInstallationFromV2(pluginId);
      if (actual.scope != scope && installations != null && installations.isNotEmpty) {
        if (actual.scope == PluginScope.project) {
          return PluginOperationResult(
            success: false,
            message:
                'Plugin "$plugin" is enabled at project scope. '
                'To disable just for you: neomclaw plugin disable $plugin --scope local',
          );
        }
        return PluginOperationResult(
          success: false,
          message:
              'Plugin "$plugin" is installed in ${actual.scope.name} scope, '
              'not ${scope.name}. Use --scope ${actual.scope.name} to uninstall.',
        );
      }
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

    // Check if this was the last installation scope.
    final updatedData = loadInstalledPluginsV2();
    final remaining = updatedData.plugins[pluginId];
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

    final reverseDeps = findReverseDependents(pluginId, allPlugins);
    final depWarn = reverseDeps.isNotEmpty
        ? '. Warning: the following plugins depend on this: ${reverseDeps.join(', ')}'
        : '';

    return PluginOperationResult(
      success: true,
      message: 'Successfully uninstalled plugin: $pluginName (scope: ${scope.name})$depWarn',
      pluginId: pluginId,
      pluginName: pluginName,
      scope: scope,
      reverseDependents: reverseDeps.isNotEmpty ? reverseDeps : null,
    );
  }

  /// Enable a plugin.
  Future<PluginOperationResult> enablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) async {
    return _setPluginEnabled(plugin, true, scope);
  }

  /// Disable a plugin.
  Future<PluginOperationResult> disablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) async {
    return _setPluginEnabled(plugin, false, scope);
  }

  /// Disable all enabled plugins.
  Future<PluginOperationResult> disableAllPlugins() async {
    var disabledCount = 0;

    for (final scope in validInstallableScopes) {
      final settingSource = scopeToSettingSource(scope);
      final enabled = getSettingsEnabledPlugins(settingSource);
      if (enabled == null || enabled.isEmpty) continue;

      final newEnabled = <String, bool>{
        for (final entry in enabled.entries) entry.key: false,
      };
      updateSettings(settingSource, {'enabledPlugins': newEnabled});
      disabledCount += enabled.length;
    }

    clearAllCaches();

    if (disabledCount == 0) {
      return const PluginOperationResult(
        success: true,
        message: 'No enabled plugins found to disable',
      );
    }

    return PluginOperationResult(
      success: true,
      message: 'Successfully disabled $disabledCount plugin${disabledCount == 1 ? '' : 's'}',
    );
  }

  // ── Private ─────────────────────────────────────────────────────────

  Future<PluginOperationResult> _setPluginEnabled(
    String plugin,
    bool enabled, [
    PluginScope? scope,
  ]) async {
    final operation = enabled ? 'enable' : 'disable';

    // Built-in plugins: always user scope.
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
              'Plugin "$plugin" not found in settings. Use plugin@marketplace format.',
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
    final scopeValue = scopeSettings?[pluginId];

    if (scope != null &&
        scopeValue == null &&
        found != null &&
        found.scope != scope) {
      final isOverride =
          (_scopePrecedence[scope] ?? 0) > (_scopePrecedence[found.scope] ?? 0);
      if (!isOverride) {
        return PluginOperationResult(
          success: false,
          message:
              'Plugin "$plugin" is installed at ${found.scope.name} scope, '
              'not ${scope.name}. Use --scope ${found.scope.name} or omit --scope.',
        );
      }
    }

    // Write the setting.
    final current = scopeSettings ?? {};
    updateSettings(settingSource, {
      'enabledPlugins': {...current, pluginId: enabled},
    });
    clearAllCaches();

    final id = parsePluginIdentifier(pluginId);
    return PluginOperationResult(
      success: true,
      message: 'Successfully ${operation}d plugin: ${id.name} (scope: ${resolvedScope.name})',
      pluginId: pluginId,
      pluginName: id.name,
      scope: resolvedScope,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Plugin installation manager controller
// ═══════════════════════════════════════════════════════════════════════════

/// Background plugin and marketplace installation manager.
///
/// Handles automatic installation of plugins and marketplaces from trusted
/// sources without blocking startup.
class PluginInstallationController extends SintController {
  /// Current installation status.
  final installationStatus = PluginInstallationStatus().obs;

  /// Whether plugins need a refresh (marketplace updated but not yet reloaded).
  final needsRefresh = false.obs;

  /// Callback for marketplace reconciliation.
  final Future<ReconciliationResult> Function({
    required void Function(ReconciliationProgressEvent) onProgress,
  })? reconcileMarketplaces;

  /// Callback for refreshing active plugins.
  final Future<void> Function()? refreshActivePlugins;

  /// Callback for computing the marketplace diff.
  final MarketplaceDiff Function()? computeDiff;

  /// Analytics event logger.
  final void Function(String eventName, Map<String, Object?> metadata)? logEvent;

  PluginInstallationController({
    this.reconcileMarketplaces,
    this.refreshActivePlugins,
    this.computeDiff,
    this.logEvent,
  });

  /// Perform background plugin startup checks and installations.
  Future<void> performBackgroundInstallations() async {
    try {
      final diff = computeDiff?.call() ?? const MarketplaceDiff();

      final pendingNames = [
        ...diff.missing,
        ...diff.sourceChanged.map((c) => c.name),
      ];

      installationStatus.value = PluginInstallationStatus(
        marketplaces: pendingNames
            .map((name) => MarketplaceInstallStatus(
                  name: name,
                  status: InstallationStatus.pending,
                ))
            .toList(),
        plugins: const [],
      );

      if (pendingNames.isEmpty) return;

      final result = await reconcileMarketplaces?.call(
        onProgress: (event) {
          if (event is ReconciliationInstalling) {
            _updateMarketplaceStatus(event.name, InstallationStatus.installing);
          } else if (event is ReconciliationInstalled) {
            _updateMarketplaceStatus(event.name, InstallationStatus.installed);
          } else if (event is ReconciliationFailed) {
            _updateMarketplaceStatus(
              event.name,
              InstallationStatus.failed,
              event.error,
            );
          }
        },
      );

      if (result == null) return;

      logEvent?.call('tengu_marketplace_background_install', {
        'installed_count': result.installed.length,
        'updated_count': result.updated.length,
        'failed_count': result.failed.length,
        'up_to_date_count': result.upToDate.length,
      });

      if (result.installed.isNotEmpty) {
        // New marketplaces installed — auto-refresh plugins.
        try {
          await refreshActivePlugins?.call();
        } catch (_) {
          needsRefresh.value = true;
        }
      } else if (result.updated.isNotEmpty) {
        // Existing marketplaces updated — notify for /reload-plugins.
        needsRefresh.value = true;
      }
    } catch (_) {
      // Swallow — background installation must not crash.
    }
  }

  void _updateMarketplaceStatus(
    String name,
    InstallationStatus status, [
    String? error,
  ]) {
    final current = installationStatus.value;
    installationStatus.value = current.copyWith(
      marketplaces: current.marketplaces
          .map((m) => m.name == name
              ? m.copyWith(status: status, error: error)
              : m)
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Plugin CLI commands service
// ═══════════════════════════════════════════════════════════════════════════

/// CLI command result for plugins.
class PluginCliResult {
  final bool success;
  final String message;

  const PluginCliResult({required this.success, required this.message});
}

/// Telemetry field builder for plugin operations.
class PluginTelemetryFields {
  final String? pluginName;
  final String? marketplaceName;
  final bool isManaged;

  const PluginTelemetryFields({
    this.pluginName,
    this.marketplaceName,
    this.isManaged = false,
  });

  Map<String, Object?> toMap() => {
        if (pluginName != null) '_PROTO_plugin_name': pluginName,
        if (marketplaceName != null) '_PROTO_marketplace_name': marketplaceName,
        'is_managed': isManaged,
      };
}

/// Build telemetry fields for a plugin CLI command.
PluginTelemetryFields buildPluginTelemetryFields(
  String name,
  String? marketplace,
  Set<String> managedPluginNames,
) {
  return PluginTelemetryFields(
    pluginName: name,
    marketplaceName: marketplace,
    isManaged: managedPluginNames.contains(name),
  );
}

/// Classify a plugin command error for analytics.
String classifyPluginCommandError(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('not found')) return 'not_found';
  if (message.contains('blocked')) return 'blocked_by_policy';
  if (message.contains('scope')) return 'scope_mismatch';
  if (message.contains('network') || message.contains('timeout')) return 'network';
  return 'unknown';
}

/// CLI command wrappers for plugin operations.
///
/// These provide thin wrappers around [PluginOperationsService] that handle
/// CLI-specific concerns like console output and analytics logging.
class PluginCliService {
  final PluginOperationsService operations;
  final void Function(String eventName, Map<String, Object?> metadata) logEvent;
  final Set<String> Function() getManagedPluginNames;
  final void Function(String message) writeOutput;
  final void Function(String message) writeError;

  PluginCliService({
    required this.operations,
    required this.logEvent,
    required this.getManagedPluginNames,
    required this.writeOutput,
    required this.writeError,
  });

  /// CLI: Install a plugin.
  Future<PluginCliResult> installPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
  ]) async {
    try {
      final result = await operations.installPlugin(plugin, scope);
      if (!result.success) {
        return PluginCliResult(success: false, message: result.message);
      }

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

      return PluginCliResult(success: true, message: result.message);
    } catch (e) {
      _handleError(e, 'install', plugin);
      return PluginCliResult(success: false, message: e.toString());
    }
  }

  /// CLI: Uninstall a plugin.
  Future<PluginCliResult> uninstallPlugin(
    String plugin, [
    PluginScope scope = PluginScope.user,
    bool keepData = false,
  ]) async {
    try {
      final result = await operations.uninstallPlugin(plugin, scope, !keepData);
      if (!result.success) {
        return PluginCliResult(success: false, message: result.message);
      }

      final id = parsePluginIdentifier(result.pluginId ?? plugin);
      logEvent('tengu_plugin_uninstalled_cli', {
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
        'scope': (result.scope ?? scope).name,
      });

      return PluginCliResult(success: true, message: result.message);
    } catch (e) {
      _handleError(e, 'uninstall', plugin);
      return PluginCliResult(success: false, message: e.toString());
    }
  }

  /// CLI: Enable a plugin.
  Future<PluginCliResult> enablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) async {
    try {
      final result = await operations.enablePlugin(plugin, scope);
      if (!result.success) {
        return PluginCliResult(success: false, message: result.message);
      }

      final id = parsePluginIdentifier(result.pluginId ?? plugin);
      logEvent('tengu_plugin_enabled_cli', {
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
        'scope': result.scope?.name,
      });

      return PluginCliResult(success: true, message: result.message);
    } catch (e) {
      _handleError(e, 'enable', plugin);
      return PluginCliResult(success: false, message: e.toString());
    }
  }

  /// CLI: Disable a plugin.
  Future<PluginCliResult> disablePlugin(
    String plugin, [
    PluginScope? scope,
  ]) async {
    try {
      final result = await operations.disablePlugin(plugin, scope);
      if (!result.success) {
        return PluginCliResult(success: false, message: result.message);
      }

      final id = parsePluginIdentifier(result.pluginId ?? plugin);
      logEvent('tengu_plugin_disabled_cli', {
        ...buildPluginTelemetryFields(
          id.name,
          id.marketplace,
          getManagedPluginNames(),
        ).toMap(),
        'scope': result.scope?.name,
      });

      return PluginCliResult(success: true, message: result.message);
    } catch (e) {
      _handleError(e, 'disable', plugin);
      return PluginCliResult(success: false, message: e.toString());
    }
  }

  /// CLI: Disable all plugins.
  Future<PluginCliResult> disableAllPlugins() async {
    try {
      final result = await operations.disableAllPlugins();
      if (!result.success) {
        return PluginCliResult(success: false, message: result.message);
      }
      logEvent('tengu_plugin_disabled_all_cli', {});
      return PluginCliResult(success: true, message: result.message);
    } catch (e) {
      _handleError(e, 'disable-all');
      return PluginCliResult(success: false, message: e.toString());
    }
  }

  void _handleError(Object error, String command, [String? plugin]) {
    final id = plugin != null ? parsePluginIdentifier(plugin) : null;
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
}
