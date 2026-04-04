// Configuration manager — port of neom_claw/src/utils/config.ts.
// Global and project config persistence, trust dialog, config caching,
// migration, and project-scoped settings.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

// ─── Types ───

/// Image dimension info for coordinate mapping.
class PastedContent {
  final int id;
  final String type; // 'text' or 'image'
  final String content;
  final String? mediaType;
  final String? filename;
  final ImageDimensions? dimensions;
  final String? sourcePath;

  const PastedContent({
    required this.id,
    required this.type,
    required this.content,
    this.mediaType,
    this.filename,
    this.dimensions,
    this.sourcePath,
  });

  factory PastedContent.fromJson(Map<String, dynamic> json) {
    return PastedContent(
      id: json['id'] as int,
      type: json['type'] as String,
      content: json['content'] as String,
      mediaType: json['mediaType'] as String?,
      filename: json['filename'] as String?,
      dimensions: json['dimensions'] != null
          ? ImageDimensions.fromJson(json['dimensions'] as Map<String, dynamic>)
          : null,
      sourcePath: json['sourcePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'content': content,
    if (mediaType != null) 'mediaType': mediaType,
    if (filename != null) 'filename': filename,
    if (dimensions != null) 'dimensions': dimensions!.toJson(),
    if (sourcePath != null) 'sourcePath': sourcePath,
  };
}

/// Image dimensions.
class ImageDimensions {
  final int width;
  final int height;
  final int? originalWidth;
  final int? originalHeight;

  const ImageDimensions({
    required this.width,
    required this.height,
    this.originalWidth,
    this.originalHeight,
  });

  factory ImageDimensions.fromJson(Map<String, dynamic> json) {
    return ImageDimensions(
      width: json['width'] as int,
      height: json['height'] as int,
      originalWidth: json['originalWidth'] as int?,
      originalHeight: json['originalHeight'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    if (originalWidth != null) 'originalWidth': originalWidth,
    if (originalHeight != null) 'originalHeight': originalHeight,
  };
}

/// History entry for prompt history.
class HistoryEntry {
  final String display;
  final Map<int, PastedContent> pastedContents;

  const HistoryEntry({required this.display, this.pastedContents = const {}});

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final pastedContentsRaw =
        json['pastedContents'] as Map<String, dynamic>? ?? {};
    final pastedContents = <int, PastedContent>{};
    for (final entry in pastedContentsRaw.entries) {
      pastedContents[int.parse(entry.key)] = PastedContent.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return HistoryEntry(
      display: json['display'] as String,
      pastedContents: pastedContents,
    );
  }
}

/// Release channel for auto-updates.
enum ReleaseChannel { stable, latest }

/// Install method for the CLI.
enum InstallMethod { local, native, global, unknown }

/// Notification channel preference.
enum NotificationChannel { auto, terminal, iterm2, osascript, none }

/// Theme setting.
enum ThemeSetting { dark, light, lightHighContrast }

/// Editor mode.
enum EditorMode { normal, vim, emacs }

/// Diff tool preference.
enum DiffTool { terminal, auto }

/// Account info from OAuth.
class AccountInfo {
  final String accountUuid;
  final String emailAddress;
  final String? organizationUuid;
  final String? organizationName;
  final String? organizationRole;
  final String? workspaceRole;
  final String? displayName;
  final bool? hasExtraUsageEnabled;
  final String? billingType;
  final String? accountCreatedAt;
  final String? subscriptionCreatedAt;

  const AccountInfo({
    required this.accountUuid,
    required this.emailAddress,
    this.organizationUuid,
    this.organizationName,
    this.organizationRole,
    this.workspaceRole,
    this.displayName,
    this.hasExtraUsageEnabled,
    this.billingType,
    this.accountCreatedAt,
    this.subscriptionCreatedAt,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    return AccountInfo(
      accountUuid: json['accountUuid'] as String,
      emailAddress: json['emailAddress'] as String,
      organizationUuid: json['organizationUuid'] as String?,
      organizationName: json['organizationName'] as String?,
      organizationRole: json['organizationRole'] as String?,
      workspaceRole: json['workspaceRole'] as String?,
      displayName: json['displayName'] as String?,
      hasExtraUsageEnabled: json['hasExtraUsageEnabled'] as bool?,
      billingType: json['billingType'] as String?,
      accountCreatedAt: json['accountCreatedAt'] as String?,
      subscriptionCreatedAt: json['subscriptionCreatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'accountUuid': accountUuid,
    'emailAddress': emailAddress,
    if (organizationUuid != null) 'organizationUuid': organizationUuid,
    if (organizationName != null) 'organizationName': organizationName,
    if (organizationRole != null) 'organizationRole': organizationRole,
    if (workspaceRole != null) 'workspaceRole': workspaceRole,
    if (displayName != null) 'displayName': displayName,
    if (hasExtraUsageEnabled != null)
      'hasExtraUsageEnabled': hasExtraUsageEnabled,
    if (billingType != null) 'billingType': billingType,
    if (accountCreatedAt != null) 'accountCreatedAt': accountCreatedAt,
    if (subscriptionCreatedAt != null)
      'subscriptionCreatedAt': subscriptionCreatedAt,
  };
}

// ─── Project Config ───

/// Per-project configuration.
class ProjectConfig {
  List<String> allowedTools;
  List<String> mcpContextUris;
  Map<String, dynamic>? mcpServers;
  bool hasTrustDialogAccepted;
  bool hasCompletedProjectOnboarding;
  int projectOnboardingSeenCount;
  bool hasNeomClawMdExternalIncludesApproved;
  bool hasNeomClawMdExternalIncludesWarningShown;
  List<String>? enabledMcpjsonServers;
  List<String>? disabledMcpjsonServers;
  bool? enableAllProjectMcpServers;
  List<String>? disabledMcpServers;
  List<String>? enabledMcpServers;
  Map<String, dynamic>? activeWorktreeSession;
  String? remoteControlSpawnMode;

  // Session metrics (last session).
  double? lastCost;
  int? lastTotalInputTokens;
  int? lastTotalOutputTokens;
  String? lastSessionId;

  ProjectConfig({
    this.allowedTools = const [],
    this.mcpContextUris = const [],
    this.mcpServers,
    this.hasTrustDialogAccepted = false,
    this.hasCompletedProjectOnboarding = false,
    this.projectOnboardingSeenCount = 0,
    this.hasNeomClawMdExternalIncludesApproved = false,
    this.hasNeomClawMdExternalIncludesWarningShown = false,
    this.enabledMcpjsonServers,
    this.disabledMcpjsonServers,
    this.enableAllProjectMcpServers,
    this.disabledMcpServers,
    this.enabledMcpServers,
    this.activeWorktreeSession,
    this.remoteControlSpawnMode,
    this.lastCost,
    this.lastTotalInputTokens,
    this.lastTotalOutputTokens,
    this.lastSessionId,
  });

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    return ProjectConfig(
      allowedTools: (json['allowedTools'] as List?)?.cast<String>() ?? [],
      mcpContextUris: (json['mcpContextUris'] as List?)?.cast<String>() ?? [],
      mcpServers: json['mcpServers'] as Map<String, dynamic>?,
      hasTrustDialogAccepted: json['hasTrustDialogAccepted'] as bool? ?? false,
      hasCompletedProjectOnboarding:
          json['hasCompletedProjectOnboarding'] as bool? ?? false,
      projectOnboardingSeenCount:
          json['projectOnboardingSeenCount'] as int? ?? 0,
      lastCost: (json['lastCost'] as num?)?.toDouble(),
      lastTotalInputTokens: json['lastTotalInputTokens'] as int?,
      lastTotalOutputTokens: json['lastTotalOutputTokens'] as int?,
      lastSessionId: json['lastSessionId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'allowedTools': allowedTools,
    'mcpContextUris': mcpContextUris,
    if (mcpServers != null) 'mcpServers': mcpServers,
    'hasTrustDialogAccepted': hasTrustDialogAccepted,
    'hasCompletedProjectOnboarding': hasCompletedProjectOnboarding,
    'projectOnboardingSeenCount': projectOnboardingSeenCount,
    if (lastCost != null) 'lastCost': lastCost,
    if (lastSessionId != null) 'lastSessionId': lastSessionId,
  };
}

// ─── Global Config ───

/// Application-wide configuration.
class GlobalConfig {
  int numStartups;
  InstallMethod? installMethod;
  bool? autoUpdates;
  ThemeSetting theme;
  bool? hasCompletedOnboarding;
  String? lastReleaseNotesSeen;
  Map<String, dynamic>? mcpServers;
  NotificationChannel preferredNotifChannel;
  bool verbose;
  String? primaryApiKey;
  AccountInfo? oauthAccount;
  EditorMode? editorMode;
  bool autoCompactEnabled;
  bool showTurnDuration;
  Map<String, String> env;
  bool? hasSeenTasksHint;
  DiffTool? diffTool;
  Map<String, int> tipsHistory;
  int memoryUsageCount;
  int promptQueueUseCount;
  int btwUseCount;
  bool todoFeatureEnabled;
  bool? showExpandedTodos;
  int messageIdleNotifThresholdMs;
  bool? autoConnectIde;
  bool? autoInstallIdeExtension;
  bool fileCheckpointingEnabled;
  bool terminalProgressBarEnabled;
  bool respectGitignore;
  bool copyFullResponse;
  Map<String, ProjectConfig>? projects;
  Map<String, bool> cachedStatsigGates;
  Map<String, dynamic>? cachedGrowthBookFeatures;
  Map<String, dynamic>? customApiKeyResponses;
  String? userID;

  GlobalConfig({
    this.numStartups = 0,
    this.installMethod,
    this.autoUpdates,
    this.theme = ThemeSetting.dark,
    this.hasCompletedOnboarding,
    this.lastReleaseNotesSeen,
    this.mcpServers,
    this.preferredNotifChannel = NotificationChannel.auto,
    this.verbose = false,
    this.primaryApiKey,
    this.oauthAccount,
    this.editorMode = EditorMode.normal,
    this.autoCompactEnabled = true,
    this.showTurnDuration = true,
    this.env = const {},
    this.hasSeenTasksHint = false,
    this.diffTool = DiffTool.auto,
    this.tipsHistory = const {},
    this.memoryUsageCount = 0,
    this.promptQueueUseCount = 0,
    this.btwUseCount = 0,
    this.todoFeatureEnabled = true,
    this.showExpandedTodos = false,
    this.messageIdleNotifThresholdMs = 60000,
    this.autoConnectIde = false,
    this.autoInstallIdeExtension = true,
    this.fileCheckpointingEnabled = true,
    this.terminalProgressBarEnabled = true,
    this.respectGitignore = true,
    this.copyFullResponse = false,
    this.projects,
    this.cachedStatsigGates = const {},
    this.cachedGrowthBookFeatures,
    this.customApiKeyResponses,
    this.userID,
  });

  factory GlobalConfig.fromJson(Map<String, dynamic> json) {
    // Parse projects.
    Map<String, ProjectConfig>? projects;
    final projectsRaw = json['projects'] as Map<String, dynamic>?;
    if (projectsRaw != null) {
      projects = {};
      for (final entry in projectsRaw.entries) {
        projects[entry.key] = ProjectConfig.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return GlobalConfig(
      numStartups: json['numStartups'] as int? ?? 0,
      installMethod: _parseInstallMethod(json['installMethod'] as String?),
      autoUpdates: json['autoUpdates'] as bool?,
      theme: _parseTheme(json['theme'] as String?),
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool?,
      lastReleaseNotesSeen: json['lastReleaseNotesSeen'] as String?,
      mcpServers: json['mcpServers'] as Map<String, dynamic>?,
      preferredNotifChannel: _parseNotifChannel(
        json['preferredNotifChannel'] as String?,
      ),
      verbose: json['verbose'] as bool? ?? false,
      primaryApiKey: json['primaryApiKey'] as String?,
      oauthAccount: json['oauthAccount'] != null
          ? AccountInfo.fromJson(json['oauthAccount'] as Map<String, dynamic>)
          : null,
      editorMode: _parseEditorMode(json['editorMode'] as String?),
      autoCompactEnabled: json['autoCompactEnabled'] as bool? ?? true,
      showTurnDuration: json['showTurnDuration'] as bool? ?? true,
      env: (json['env'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      hasSeenTasksHint: json['hasSeenTasksHint'] as bool? ?? false,
      diffTool: _parseDiffTool(json['diffTool'] as String?),
      tipsHistory:
          (json['tipsHistory'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as int),
          ) ??
          {},
      memoryUsageCount: json['memoryUsageCount'] as int? ?? 0,
      promptQueueUseCount: json['promptQueueUseCount'] as int? ?? 0,
      btwUseCount: json['btwUseCount'] as int? ?? 0,
      todoFeatureEnabled: json['todoFeatureEnabled'] as bool? ?? true,
      showExpandedTodos: json['showExpandedTodos'] as bool? ?? false,
      messageIdleNotifThresholdMs:
          json['messageIdleNotifThresholdMs'] as int? ?? 60000,
      autoConnectIde: json['autoConnectIde'] as bool? ?? false,
      autoInstallIdeExtension: json['autoInstallIdeExtension'] as bool? ?? true,
      fileCheckpointingEnabled:
          json['fileCheckpointingEnabled'] as bool? ?? true,
      terminalProgressBarEnabled:
          json['terminalProgressBarEnabled'] as bool? ?? true,
      respectGitignore: json['respectGitignore'] as bool? ?? true,
      copyFullResponse: json['copyFullResponse'] as bool? ?? false,
      projects: projects,
      cachedStatsigGates:
          (json['cachedStatsigGates'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as bool),
          ) ??
          {},
      cachedGrowthBookFeatures:
          json['cachedGrowthBookFeatures'] as Map<String, dynamic>?,
      customApiKeyResponses:
          json['customApiKeyResponses'] as Map<String, dynamic>?,
      userID: json['userID'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'numStartups': numStartups,
      if (installMethod != null) 'installMethod': installMethod!.name,
      if (autoUpdates != null) 'autoUpdates': autoUpdates,
      'theme': theme.name,
      if (hasCompletedOnboarding != null)
        'hasCompletedOnboarding': hasCompletedOnboarding,
      'preferredNotifChannel': preferredNotifChannel.name,
      'verbose': verbose,
      if (oauthAccount != null) 'oauthAccount': oauthAccount!.toJson(),
      if (editorMode != null) 'editorMode': editorMode!.name,
      'autoCompactEnabled': autoCompactEnabled,
      'showTurnDuration': showTurnDuration,
      'env': env,
      'tipsHistory': tipsHistory,
      'memoryUsageCount': memoryUsageCount,
      'todoFeatureEnabled': todoFeatureEnabled,
      'respectGitignore': respectGitignore,
      'copyFullResponse': copyFullResponse,
      'cachedStatsigGates': cachedStatsigGates,
      if (cachedGrowthBookFeatures != null)
        'cachedGrowthBookFeatures': cachedGrowthBookFeatures,
    };
    if (projects != null) {
      result['projects'] = projects!.map((k, v) => MapEntry(k, v.toJson()));
    }
    return result;
  }
}

// ─── Config Manager ───

/// Keys that are safe to expose in the global config UI.
const globalConfigKeys = [
  'installMethod',
  'autoUpdates',
  'theme',
  'verbose',
  'preferredNotifChannel',
  'editorMode',
  'autoCompactEnabled',
  'showTurnDuration',
  'diffTool',
  'env',
  'todoFeatureEnabled',
  'showExpandedTodos',
  'messageIdleNotifThresholdMs',
  'autoConnectIde',
  'fileCheckpointingEnabled',
  'terminalProgressBarEnabled',
  'respectGitignore',
  'copyFullResponse',
];

/// Keys that are safe for project config UI.
const projectConfigKeys = [
  'allowedTools',
  'hasTrustDialogAccepted',
  'hasCompletedProjectOnboarding',
];

/// Check if a key is a global config key.
bool isGlobalConfigKey(String key) => globalConfigKeys.contains(key);

/// Check if a key is a project config key.
bool isProjectConfigKey(String key) => projectConfigKeys.contains(key);

/// Manages reading and writing the global config file (~/.neomclaw.json).
class ConfigManager {
  /// Path to the global config file.
  final String configFilePath;

  /// Current working directory for project config resolution.
  final String cwd;

  /// Cached config.
  GlobalConfig? _cache;

  /// Cache modification time.
  // ignore: unused_field
  DateTime? _cacheMtime;

  /// Write count for diagnostics.
  int _writeCount = 0;

  /// Trust dialog accepted cache (only transitions false -> true).
  bool _trustAccepted = false;

  ConfigManager({required this.configFilePath, required this.cwd});

  /// Get the write count for diagnostics.
  int get writeCount => _writeCount;

  /// Display threshold for write count warnings.
  static const configWriteDisplayThreshold = 20;

  /// Get the global config, reading from disk if cache is stale.
  GlobalConfig getGlobalConfig() {
    if (_cache != null) return _cache!;

    try {
      final file = File(configFilePath);
      if (!file.existsSync()) {
        _cache = GlobalConfig();
        return _cache!;
      }

      final content = file.readAsStringSync();
      final stripped = _stripBOM(content);
      final parsed = _safeParseJSON(stripped);
      if (parsed == null) {
        _cache = GlobalConfig();
        return _cache!;
      }

      _cache = _migrateConfigFields(GlobalConfig.fromJson(parsed), parsed);
      final stat = file.statSync();
      _cacheMtime = stat.modified;
      return _cache!;
    } catch (_) {
      _cache = GlobalConfig();
      return _cache!;
    }
  }

  /// Save the global config with an updater function.
  void saveGlobalConfig(GlobalConfig Function(GlobalConfig current) updater) {
    final current = getGlobalConfig();
    final updated = updater(current);
    if (identical(updated, current)) return;

    // Auth-loss guard.
    if (_wouldLoseAuthState(current, updated)) return;

    try {
      final dir = Directory(p.dirname(configFilePath));
      if (!dir.existsSync()) dir.createSync(recursive: true);

      // Remove project history to avoid config bloat.
      final toWrite = updated.toJson();
      _removeProjectHistory(toWrite);

      File(
        configFilePath,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toWrite));
      _cache = updated;
      _cacheMtime = DateTime.now();
      _writeCount++;
    } catch (e) {
      // Log but don't throw.
    }
  }

  /// Get the current project config.
  ProjectConfig getCurrentProjectConfig() {
    final config = getGlobalConfig();
    final projectPath = _getProjectPathForConfig();
    return config.projects?[projectPath] ?? ProjectConfig();
  }

  /// Save the current project config.
  void saveCurrentProjectConfig(
    ProjectConfig Function(ProjectConfig current) updater,
  ) {
    final projectPath = _getProjectPathForConfig();
    saveGlobalConfig((current) {
      final projects = Map<String, ProjectConfig>.from(current.projects ?? {});
      final currentProject = projects[projectPath] ?? ProjectConfig();
      projects[projectPath] = updater(currentProject);
      current.projects = projects;
      return current;
    });
  }

  /// Check if the trust dialog has been accepted for the cwd.
  bool checkHasTrustDialogAccepted() {
    if (_trustAccepted) return true;
    _trustAccepted = _computeTrustDialogAccepted();
    return _trustAccepted;
  }

  /// Check if a path is trusted (walks parents).
  bool isPathTrusted(String dir) {
    final config = getGlobalConfig();
    var currentPath = _normalizePathForConfigKey(p.normalize(dir));
    while (true) {
      if (config.projects?[currentPath]?.hasTrustDialogAccepted == true) {
        return true;
      }
      final parentPath = _normalizePathForConfigKey(
        p.normalize(p.join(currentPath, '..')),
      );
      if (parentPath == currentPath) return false;
      currentPath = parentPath;
    }
  }

  /// Reset trust dialog cache for testing.
  void resetTrustDialogAcceptedCacheForTesting() {
    _trustAccepted = false;
  }

  /// Invalidate the config cache, forcing a re-read on next access.
  void invalidateCache() {
    _cache = null;
    _cacheMtime = null;
  }

  // ─── Private Helpers ───

  bool _computeTrustDialogAccepted() {
    final config = getGlobalConfig();
    var currentPath = _normalizePathForConfigKey(cwd);
    while (true) {
      if (config.projects?[currentPath]?.hasTrustDialogAccepted == true) {
        return true;
      }
      final parentPath = _normalizePathForConfigKey(
        p.normalize(p.join(currentPath, '..')),
      );
      if (parentPath == currentPath) break;
      currentPath = parentPath;
    }
    return false;
  }

  String _getProjectPathForConfig() {
    return _normalizePathForConfigKey(cwd);
  }

  String _normalizePathForConfigKey(String pathStr) {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && pathStr.startsWith(home)) {
      return '~${pathStr.substring(home.length)}';
    }
    return pathStr;
  }

  bool _wouldLoseAuthState(GlobalConfig cached, GlobalConfig fresh) {
    final lostOauth = cached.oauthAccount != null && fresh.oauthAccount == null;
    final lostOnboarding =
        cached.hasCompletedOnboarding == true &&
        fresh.hasCompletedOnboarding != true;
    return lostOauth || lostOnboarding;
  }

  GlobalConfig _migrateConfigFields(
    GlobalConfig config,
    Map<String, dynamic> raw,
  ) {
    if (config.installMethod != null) return config;

    // Migrate legacy autoUpdaterStatus field.
    final legacy = raw['autoUpdaterStatus'] as String?;
    if (legacy == null) return config;

    switch (legacy) {
      case 'migrated':
        config.installMethod = InstallMethod.local;
      case 'installed':
        config.installMethod = InstallMethod.native;
      case 'disabled':
        config.autoUpdates = false;
      case 'enabled':
      case 'no_permissions':
      case 'not_configured':
        config.installMethod = InstallMethod.global;
    }
    return config;
  }

  void _removeProjectHistory(Map<String, dynamic> configJson) {
    final projects = configJson['projects'] as Map<String, dynamic>?;
    if (projects == null) return;
    for (final entry in projects.entries) {
      final project = entry.value as Map<String, dynamic>;
      project.remove('history');
    }
  }

  String _stripBOM(String content) {
    if (content.startsWith('\uFEFF')) return content.substring(1);
    return content;
  }

  Map<String, dynamic>? _safeParseJSON(String content) {
    try {
      final parsed = jsonDecode(content);
      if (parsed is Map<String, dynamic>) return parsed;
      return null;
    } catch (_) {
      return null;
    }
  }
}

// ─── Enum Parsers ───

InstallMethod? _parseInstallMethod(String? value) {
  if (value == null) return null;
  return InstallMethod.values.where((e) => e.name == value).firstOrNull;
}

ThemeSetting _parseTheme(String? value) {
  if (value == null) return ThemeSetting.dark;
  return ThemeSetting.values.where((e) => e.name == value).firstOrNull ??
      ThemeSetting.dark;
}

NotificationChannel _parseNotifChannel(String? value) {
  if (value == null) return NotificationChannel.auto;
  return NotificationChannel.values.where((e) => e.name == value).firstOrNull ??
      NotificationChannel.auto;
}

EditorMode? _parseEditorMode(String? value) {
  if (value == null) return EditorMode.normal;
  return EditorMode.values.where((e) => e.name == value).firstOrNull ??
      EditorMode.normal;
}

DiffTool? _parseDiffTool(String? value) {
  if (value == null) return DiffTool.auto;
  return DiffTool.values.where((e) => e.name == value).firstOrNull ??
      DiffTool.auto;
}
