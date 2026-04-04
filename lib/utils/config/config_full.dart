/// Full configuration management: reading, writing, merging from multiple
/// sources (project, user/global, system).
///
/// Port of neom_claw/src/utils/config.ts (1825 LOC).
/// Contains all types, defaults, reading, writing, caching, backup/restore,
/// locked writes, freshness watching, trust dialog traversal, auto-updater
/// config, memory paths, migration, and the complete field sets.
library;

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Image dimension info for coordinate mapping (only set when image was resized)
// ---------------------------------------------------------------------------

class ImageDimensions {
  final int width;
  final int height;

  const ImageDimensions({required this.width, required this.height});

  factory ImageDimensions.fromJson(Map<String, dynamic> json) =>
      ImageDimensions(
        width: json['width'] as int,
        height: json['height'] as int,
      );

  Map<String, dynamic> toJson() => {'width': width, 'height': height};
}

// ---------------------------------------------------------------------------
// PastedContent
// ---------------------------------------------------------------------------

class PastedContent {
  final int id;
  final String type; // 'text' | 'image'
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

  bool get isImage => type == 'image';
  bool get isText => type == 'text';

  factory PastedContent.fromJson(Map<String, dynamic> json) => PastedContent(
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

// ---------------------------------------------------------------------------
// History entry types
// ---------------------------------------------------------------------------

class SerializedStructuredHistoryEntry {
  final String display;
  final Map<int, PastedContent>? pastedContents;
  final String? pastedText;

  const SerializedStructuredHistoryEntry({
    required this.display,
    this.pastedContents,
    this.pastedText,
  });

  factory SerializedStructuredHistoryEntry.fromJson(Map<String, dynamic> json) {
    final raw = json['pastedContents'] as Map<String, dynamic>?;
    return SerializedStructuredHistoryEntry(
      display: json['display'] as String,
      pastedContents: raw?.map(
        (k, v) => MapEntry(
          int.parse(k),
          PastedContent.fromJson(v as Map<String, dynamic>),
        ),
      ),
      pastedText: json['pastedText'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'display': display,
    if (pastedContents != null)
      'pastedContents': pastedContents!.map(
        (k, v) => MapEntry(k.toString(), v.toJson()),
      ),
    if (pastedText != null) 'pastedText': pastedText,
  };
}

class HistoryEntry {
  final String display;
  final Map<int, PastedContent> pastedContents;

  const HistoryEntry({required this.display, required this.pastedContents});
}

// ---------------------------------------------------------------------------
// Enums & typedefs
// ---------------------------------------------------------------------------

enum ReleaseChannel { stable, latest }

enum InstallMethod { local, native, global, unknown }

enum ThemeSetting { dark, light, lightHighContrast, darkHighContrast }

enum EditorMode { normal, vim, emacs }

enum DiffTool { terminal, auto }

enum NotificationChannel {
  auto,
  iterm2,
  terminalBell,
  terminalNotifier,
  applescript,
  native,
  none,
}

enum MemoryType { user, local, project, managed, autoMem }

typedef OutputStyle = String;

// ---------------------------------------------------------------------------
// AutoUpdaterDisabledReason — sealed class for union
// ---------------------------------------------------------------------------

sealed class AutoUpdaterDisabledReason {
  const AutoUpdaterDisabledReason();

  String format() => switch (this) {
    AutoUpdaterDisabledDevelopment() => 'development build',
    AutoUpdaterDisabledEnv(:final envVar) => '$envVar set',
    AutoUpdaterDisabledConfig() => 'config',
  };
}

class AutoUpdaterDisabledDevelopment extends AutoUpdaterDisabledReason {
  const AutoUpdaterDisabledDevelopment();
}

class AutoUpdaterDisabledEnv extends AutoUpdaterDisabledReason {
  final String envVar;
  const AutoUpdaterDisabledEnv({required this.envVar});
}

class AutoUpdaterDisabledConfig extends AutoUpdaterDisabledReason {
  const AutoUpdaterDisabledConfig();
}

// ---------------------------------------------------------------------------
// AccountInfo
// ---------------------------------------------------------------------------

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

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
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

// ---------------------------------------------------------------------------
// ActiveWorktreeSession
// ---------------------------------------------------------------------------

class ActiveWorktreeSession {
  final String originalCwd;
  final String worktreePath;
  final String worktreeName;
  final String? originalBranch;
  final String sessionId;
  final bool? hookBased;

  const ActiveWorktreeSession({
    required this.originalCwd,
    required this.worktreePath,
    required this.worktreeName,
    this.originalBranch,
    required this.sessionId,
    this.hookBased,
  });

  factory ActiveWorktreeSession.fromJson(Map<String, dynamic> json) =>
      ActiveWorktreeSession(
        originalCwd: json['originalCwd'] as String,
        worktreePath: json['worktreePath'] as String,
        worktreeName: json['worktreeName'] as String,
        originalBranch: json['originalBranch'] as String?,
        sessionId: json['sessionId'] as String,
        hookBased: json['hookBased'] as bool?,
      );

  Map<String, dynamic> toJson() => {
    'originalCwd': originalCwd,
    'worktreePath': worktreePath,
    'worktreeName': worktreeName,
    if (originalBranch != null) 'originalBranch': originalBranch,
    'sessionId': sessionId,
    if (hookBased != null) 'hookBased': hookBased,
  };
}

// ---------------------------------------------------------------------------
// ModelUsageMetrics
// ---------------------------------------------------------------------------

class ModelUsageMetrics {
  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
  final int webSearchRequests;
  final double costUSD;

  const ModelUsageMetrics({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadInputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.webSearchRequests = 0,
    this.costUSD = 0.0,
  });

  factory ModelUsageMetrics.fromJson(Map<String, dynamic> json) =>
      ModelUsageMetrics(
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        cacheReadInputTokens:
            (json['cacheReadInputTokens'] as num?)?.toInt() ?? 0,
        cacheCreationInputTokens:
            (json['cacheCreationInputTokens'] as num?)?.toInt() ?? 0,
        webSearchRequests: (json['webSearchRequests'] as num?)?.toInt() ?? 0,
        costUSD: (json['costUSD'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadInputTokens': cacheReadInputTokens,
    'cacheCreationInputTokens': cacheCreationInputTokens,
    'webSearchRequests': webSearchRequests,
    'costUSD': costUSD,
  };
}

// ---------------------------------------------------------------------------
// FeedbackSurveyState
// ---------------------------------------------------------------------------

class FeedbackSurveyState {
  final int? lastShownTime;
  const FeedbackSurveyState({this.lastShownTime});

  factory FeedbackSurveyState.fromJson(Map<String, dynamic> json) =>
      FeedbackSurveyState(lastShownTime: json['lastShownTime'] as int?);

  Map<String, dynamic> toJson() => {
    if (lastShownTime != null) 'lastShownTime': lastShownTime,
  };
}

// ---------------------------------------------------------------------------
// S1mAccessCacheEntry
// ---------------------------------------------------------------------------

class S1mAccessCacheEntry {
  final bool hasAccess;
  final bool? hasAccessNotAsDefault;
  final int timestamp;

  const S1mAccessCacheEntry({
    required this.hasAccess,
    this.hasAccessNotAsDefault,
    required this.timestamp,
  });

  factory S1mAccessCacheEntry.fromJson(Map<String, dynamic> json) =>
      S1mAccessCacheEntry(
        hasAccess: json['hasAccess'] as bool? ?? false,
        hasAccessNotAsDefault: json['hasAccessNotAsDefault'] as bool?,
        timestamp: json['timestamp'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'hasAccess': hasAccess,
    if (hasAccessNotAsDefault != null)
      'hasAccessNotAsDefault': hasAccessNotAsDefault,
    'timestamp': timestamp,
  };
}

// ---------------------------------------------------------------------------
// SkillUsageEntry
// ---------------------------------------------------------------------------

class SkillUsageEntry {
  final int usageCount;
  final int lastUsedAt;

  const SkillUsageEntry({required this.usageCount, required this.lastUsedAt});

  factory SkillUsageEntry.fromJson(Map<String, dynamic> json) =>
      SkillUsageEntry(
        usageCount: json['usageCount'] as int? ?? 0,
        lastUsedAt: json['lastUsedAt'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'usageCount': usageCount,
    'lastUsedAt': lastUsedAt,
  };
}

// ---------------------------------------------------------------------------
// NeomClawHints
// ---------------------------------------------------------------------------

class NeomClawHints {
  final List<String>? plugin;
  final bool? disabled;

  const NeomClawHints({this.plugin, this.disabled});

  factory NeomClawHints.fromJson(Map<String, dynamic> json) => NeomClawHints(
    plugin: (json['plugin'] as List?)?.cast<String>(),
    disabled: json['disabled'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    if (plugin != null) 'plugin': plugin,
    if (disabled != null) 'disabled': disabled,
  };
}

// ---------------------------------------------------------------------------
// ChromeExtensionPairing
// ---------------------------------------------------------------------------

class ChromeExtensionPairing {
  final String? pairedDeviceId;
  final String? pairedDeviceName;

  const ChromeExtensionPairing({this.pairedDeviceId, this.pairedDeviceName});

  factory ChromeExtensionPairing.fromJson(Map<String, dynamic> json) =>
      ChromeExtensionPairing(
        pairedDeviceId: json['pairedDeviceId'] as String?,
        pairedDeviceName: json['pairedDeviceName'] as String?,
      );

  Map<String, dynamic> toJson() => {
    if (pairedDeviceId != null) 'pairedDeviceId': pairedDeviceId,
    if (pairedDeviceName != null) 'pairedDeviceName': pairedDeviceName,
  };
}

// ---------------------------------------------------------------------------
// ProjectConfig
// ---------------------------------------------------------------------------

class ProjectConfig {
  List<String> allowedTools;
  List<String> mcpContextUris;
  Map<String, dynamic>? mcpServers;
  double? lastAPIDuration;
  double? lastAPIDurationWithoutRetries;
  double? lastToolDuration;
  double? lastCost;
  double? lastDuration;
  int? lastLinesAdded;
  int? lastLinesRemoved;
  int? lastTotalInputTokens;
  int? lastTotalOutputTokens;
  int? lastTotalCacheCreationInputTokens;
  int? lastTotalCacheReadInputTokens;
  int? lastTotalWebSearchRequests;
  double? lastFpsAverage;
  double? lastFpsLow1Pct;
  String? lastSessionId;
  Map<String, ModelUsageMetrics>? lastModelUsage;
  Map<String, int>? lastSessionMetrics;
  List<String>? exampleFiles;
  int? exampleFilesGeneratedAt;
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

  ProjectConfig({
    this.allowedTools = const [],
    this.mcpContextUris = const [],
    this.mcpServers,
    this.lastAPIDuration,
    this.lastAPIDurationWithoutRetries,
    this.lastToolDuration,
    this.lastCost,
    this.lastDuration,
    this.lastLinesAdded,
    this.lastLinesRemoved,
    this.lastTotalInputTokens,
    this.lastTotalOutputTokens,
    this.lastTotalCacheCreationInputTokens,
    this.lastTotalCacheReadInputTokens,
    this.lastTotalWebSearchRequests,
    this.lastFpsAverage,
    this.lastFpsLow1Pct,
    this.lastSessionId,
    this.lastModelUsage,
    this.lastSessionMetrics,
    this.exampleFiles,
    this.exampleFilesGeneratedAt,
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
  });

  static ProjectConfig defaultConfig() =>
      ProjectConfig(enabledMcpjsonServers: [], disabledMcpjsonServers: []);

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    Map<String, ModelUsageMetrics>? modelUsage;
    final raw = json['lastModelUsage'] as Map<String, dynamic>?;
    if (raw != null) {
      modelUsage = raw.map(
        (k, v) =>
            MapEntry(k, ModelUsageMetrics.fromJson(v as Map<String, dynamic>)),
      );
    }

    return ProjectConfig(
      allowedTools: (json['allowedTools'] as List?)?.cast<String>() ?? [],
      mcpContextUris: (json['mcpContextUris'] as List?)?.cast<String>() ?? [],
      mcpServers: json['mcpServers'] as Map<String, dynamic>?,
      lastAPIDuration: (json['lastAPIDuration'] as num?)?.toDouble(),
      lastAPIDurationWithoutRetries:
          (json['lastAPIDurationWithoutRetries'] as num?)?.toDouble(),
      lastToolDuration: (json['lastToolDuration'] as num?)?.toDouble(),
      lastCost: (json['lastCost'] as num?)?.toDouble(),
      lastDuration: (json['lastDuration'] as num?)?.toDouble(),
      lastLinesAdded: json['lastLinesAdded'] as int?,
      lastLinesRemoved: json['lastLinesRemoved'] as int?,
      lastTotalInputTokens: json['lastTotalInputTokens'] as int?,
      lastTotalOutputTokens: json['lastTotalOutputTokens'] as int?,
      lastTotalCacheCreationInputTokens:
          json['lastTotalCacheCreationInputTokens'] as int?,
      lastTotalCacheReadInputTokens:
          json['lastTotalCacheReadInputTokens'] as int?,
      lastTotalWebSearchRequests: json['lastTotalWebSearchRequests'] as int?,
      lastFpsAverage: (json['lastFpsAverage'] as num?)?.toDouble(),
      lastFpsLow1Pct: (json['lastFpsLow1Pct'] as num?)?.toDouble(),
      lastSessionId: json['lastSessionId'] as String?,
      lastModelUsage: modelUsage,
      lastSessionMetrics: (json['lastSessionMetrics'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())),
      exampleFiles: (json['exampleFiles'] as List?)?.cast<String>(),
      exampleFilesGeneratedAt: json['exampleFilesGeneratedAt'] as int?,
      hasTrustDialogAccepted: json['hasTrustDialogAccepted'] as bool? ?? false,
      hasCompletedProjectOnboarding:
          json['hasCompletedProjectOnboarding'] as bool? ?? false,
      projectOnboardingSeenCount:
          json['projectOnboardingSeenCount'] as int? ?? 0,
      hasNeomClawMdExternalIncludesApproved:
          json['hasNeomClawMdExternalIncludesApproved'] as bool? ?? false,
      hasNeomClawMdExternalIncludesWarningShown:
          json['hasNeomClawMdExternalIncludesWarningShown'] as bool? ?? false,
      enabledMcpjsonServers: (json['enabledMcpjsonServers'] as List?)
          ?.cast<String>(),
      disabledMcpjsonServers: (json['disabledMcpjsonServers'] as List?)
          ?.cast<String>(),
      enableAllProjectMcpServers: json['enableAllProjectMcpServers'] as bool?,
      disabledMcpServers: (json['disabledMcpServers'] as List?)?.cast<String>(),
      enabledMcpServers: (json['enabledMcpServers'] as List?)?.cast<String>(),
      activeWorktreeSession:
          json['activeWorktreeSession'] as Map<String, dynamic>?,
      remoteControlSpawnMode: json['remoteControlSpawnMode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'allowedTools': allowedTools,
    'mcpContextUris': mcpContextUris,
    if (mcpServers != null) 'mcpServers': mcpServers,
    if (lastAPIDuration != null) 'lastAPIDuration': lastAPIDuration,
    if (lastCost != null) 'lastCost': lastCost,
    if (lastDuration != null) 'lastDuration': lastDuration,
    if (lastLinesAdded != null) 'lastLinesAdded': lastLinesAdded,
    if (lastLinesRemoved != null) 'lastLinesRemoved': lastLinesRemoved,
    if (lastTotalInputTokens != null)
      'lastTotalInputTokens': lastTotalInputTokens,
    if (lastTotalOutputTokens != null)
      'lastTotalOutputTokens': lastTotalOutputTokens,
    if (lastSessionId != null) 'lastSessionId': lastSessionId,
    if (lastModelUsage != null)
      'lastModelUsage': lastModelUsage!.map((k, v) => MapEntry(k, v.toJson())),
    'hasTrustDialogAccepted': hasTrustDialogAccepted,
    'hasCompletedProjectOnboarding': hasCompletedProjectOnboarding,
    'projectOnboardingSeenCount': projectOnboardingSeenCount,
    if (activeWorktreeSession != null)
      'activeWorktreeSession': activeWorktreeSession,
    if (remoteControlSpawnMode != null)
      'remoteControlSpawnMode': remoteControlSpawnMode,
  };
}

// ---------------------------------------------------------------------------
// GlobalConfig
// ---------------------------------------------------------------------------

class GlobalConfig {
  String? apiKeyHelper;
  Map<String, ProjectConfig>? projects;
  int numStartups;
  InstallMethod? installMethod;
  bool? autoUpdates;
  bool? autoUpdatesProtectedForNative;
  int? doctorShownAtSession;
  String? userID;
  ThemeSetting theme;
  bool? hasCompletedOnboarding;
  String? lastOnboardingVersion;
  String? lastReleaseNotesSeen;
  int? changelogLastFetched;
  Map<String, dynamic>? mcpServers;
  List<String>? neomClawAiMcpEverConnected;
  NotificationChannel preferredNotifChannel;
  String? customNotifyCommand;
  bool verbose;
  Map<String, dynamic>? customApiKeyResponses;
  String? primaryApiKey;
  bool? hasAcknowledgedCostThreshold;
  bool? hasSeenUndercoverAutoNotice;
  AccountInfo? oauthAccount;
  EditorMode editorMode;
  bool? bypassPermissionsModeAccepted;
  bool? hasUsedBackslashReturn;
  bool autoCompactEnabled;
  bool showTurnDuration;
  Map<String, String> env;
  bool hasSeenTasksHint;
  bool? hasUsedStash;
  bool? hasUsedBackgroundTask;
  int? queuedCommandUpHintCount;
  DiffTool diffTool;
  Map<String, int> tipsHistory;
  int memoryUsageCount;
  int promptQueueUseCount;
  int btwUseCount;
  bool todoFeatureEnabled;
  bool showExpandedTodos;
  bool? showSpinnerTree;
  String? firstStartTime;
  int messageIdleNotifThresholdMs;
  bool autoConnectIde;
  bool autoInstallIdeExtension;
  bool fileCheckpointingEnabled;
  bool terminalProgressBarEnabled;
  bool? showStatusInTerminalTab;
  bool? taskCompleteNotifEnabled;
  bool? inputNeededNotifEnabled;
  bool? agentPushNotifEnabled;
  Map<String, bool> cachedStatsigGates;
  Map<String, dynamic>? cachedDynamicConfigs;
  Map<String, dynamic>? cachedGrowthBookFeatures;
  Map<String, dynamic>? growthBookOverrides;
  bool respectGitignore;
  bool copyFullResponse;
  bool? copyOnSelect;
  Map<String, List<String>>? githubRepoPaths;
  String? deepLinkTerminal;
  Map<String, SkillUsageEntry>? skillUsage;
  bool? remoteControlAtStartup;
  String? cachedExtraUsageDisabledReason;
  bool? speculationEnabled;
  Map<String, dynamic>? clientDataCache;
  int? migrationVersion;
  FeedbackSurveyState? feedbackSurveyState;
  bool? transcriptShareDismissed;
  ChromeExtensionPairing? chromeExtension;
  NeomClawHints? neomClawHints;
  bool? permissionExplainerEnabled;
  String? teammateMode;
  String? teammateDefaultModel;
  bool? prStatusFooterEnabled;
  bool? remoteDialogSeen;
  int? lastPlanModeUse;
  String? neomClawFirstTokenDate;

  GlobalConfig({
    this.apiKeyHelper,
    this.projects,
    this.numStartups = 0,
    this.installMethod,
    this.autoUpdates,
    this.autoUpdatesProtectedForNative,
    this.doctorShownAtSession,
    this.userID,
    this.theme = ThemeSetting.dark,
    this.hasCompletedOnboarding,
    this.lastOnboardingVersion,
    this.lastReleaseNotesSeen,
    this.changelogLastFetched,
    this.mcpServers,
    this.neomClawAiMcpEverConnected,
    this.preferredNotifChannel = NotificationChannel.auto,
    this.customNotifyCommand,
    this.verbose = false,
    this.customApiKeyResponses,
    this.primaryApiKey,
    this.hasAcknowledgedCostThreshold,
    this.hasSeenUndercoverAutoNotice,
    this.oauthAccount,
    this.editorMode = EditorMode.normal,
    this.bypassPermissionsModeAccepted,
    this.hasUsedBackslashReturn,
    this.autoCompactEnabled = true,
    this.showTurnDuration = true,
    this.env = const {},
    this.hasSeenTasksHint = false,
    this.hasUsedStash,
    this.hasUsedBackgroundTask,
    this.queuedCommandUpHintCount,
    this.diffTool = DiffTool.auto,
    this.tipsHistory = const {},
    this.memoryUsageCount = 0,
    this.promptQueueUseCount = 0,
    this.btwUseCount = 0,
    this.todoFeatureEnabled = true,
    this.showExpandedTodos = false,
    this.showSpinnerTree,
    this.firstStartTime,
    this.messageIdleNotifThresholdMs = 60000,
    this.autoConnectIde = false,
    this.autoInstallIdeExtension = true,
    this.fileCheckpointingEnabled = true,
    this.terminalProgressBarEnabled = true,
    this.showStatusInTerminalTab,
    this.taskCompleteNotifEnabled,
    this.inputNeededNotifEnabled,
    this.agentPushNotifEnabled,
    this.cachedStatsigGates = const {},
    this.cachedDynamicConfigs,
    this.cachedGrowthBookFeatures,
    this.growthBookOverrides,
    this.respectGitignore = true,
    this.copyFullResponse = false,
    this.copyOnSelect,
    this.githubRepoPaths,
    this.deepLinkTerminal,
    this.skillUsage,
    this.remoteControlAtStartup,
    this.cachedExtraUsageDisabledReason,
    this.speculationEnabled,
    this.clientDataCache,
    this.migrationVersion,
    this.feedbackSurveyState,
    this.transcriptShareDismissed,
    this.chromeExtension,
    this.neomClawHints,
    this.permissionExplainerEnabled,
    this.teammateMode,
    this.teammateDefaultModel,
    this.prStatusFooterEnabled,
    this.remoteDialogSeen,
    this.lastPlanModeUse,
    this.neomClawFirstTokenDate,
  });

  /// Factory for a fresh default.
  factory GlobalConfig.defaults() => GlobalConfig();

  factory GlobalConfig.fromJson(Map<String, dynamic> json) {
    final rawProjects = json['projects'] as Map<String, dynamic>?;
    Map<String, SkillUsageEntry>? skillUsage;
    final rawSkill = json['skillUsage'] as Map<String, dynamic>?;
    if (rawSkill != null) {
      skillUsage = rawSkill.map(
        (k, v) =>
            MapEntry(k, SkillUsageEntry.fromJson(v as Map<String, dynamic>)),
      );
    }

    return GlobalConfig(
      apiKeyHelper: json['apiKeyHelper'] as String?,
      projects: rawProjects?.map(
        (k, v) =>
            MapEntry(k, ProjectConfig.fromJson(v as Map<String, dynamic>)),
      ),
      numStartups: (json['numStartups'] as int?) ?? 0,
      installMethod: _parseInstallMethod(json['installMethod'] as String?),
      autoUpdates: json['autoUpdates'] as bool?,
      autoUpdatesProtectedForNative:
          json['autoUpdatesProtectedForNative'] as bool?,
      userID: json['userID'] as String?,
      theme: _parseTheme(json['theme'] as String?),
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool?,
      lastOnboardingVersion: json['lastOnboardingVersion'] as String?,
      preferredNotifChannel: _parseNotifChannel(
        json['preferredNotifChannel'] as String?,
      ),
      verbose: (json['verbose'] as bool?) ?? false,
      customApiKeyResponses:
          json['customApiKeyResponses'] as Map<String, dynamic>?,
      primaryApiKey: json['primaryApiKey'] as String?,
      oauthAccount: json['oauthAccount'] != null
          ? AccountInfo.fromJson(json['oauthAccount'] as Map<String, dynamic>)
          : null,
      editorMode: _parseEditorMode(json['editorMode'] as String?),
      autoCompactEnabled: (json['autoCompactEnabled'] as bool?) ?? true,
      showTurnDuration: (json['showTurnDuration'] as bool?) ?? true,
      env:
          (json['env'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      diffTool: _parseDiffTool(json['diffTool'] as String?),
      tipsHistory:
          (json['tipsHistory'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, (v as num).toInt()),
          ) ??
          {},
      memoryUsageCount: (json['memoryUsageCount'] as int?) ?? 0,
      promptQueueUseCount: (json['promptQueueUseCount'] as int?) ?? 0,
      btwUseCount: (json['btwUseCount'] as int?) ?? 0,
      todoFeatureEnabled: (json['todoFeatureEnabled'] as bool?) ?? true,
      showExpandedTodos: (json['showExpandedTodos'] as bool?) ?? false,
      messageIdleNotifThresholdMs:
          (json['messageIdleNotifThresholdMs'] as int?) ?? 60000,
      autoConnectIde: (json['autoConnectIde'] as bool?) ?? false,
      autoInstallIdeExtension:
          (json['autoInstallIdeExtension'] as bool?) ?? true,
      fileCheckpointingEnabled:
          (json['fileCheckpointingEnabled'] as bool?) ?? true,
      terminalProgressBarEnabled:
          (json['terminalProgressBarEnabled'] as bool?) ?? true,
      cachedStatsigGates:
          (json['cachedStatsigGates'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as bool),
          ) ??
          {},
      respectGitignore: (json['respectGitignore'] as bool?) ?? true,
      copyFullResponse: (json['copyFullResponse'] as bool?) ?? false,
      remoteControlAtStartup: json['remoteControlAtStartup'] as bool?,
      migrationVersion: json['migrationVersion'] as int?,
      skillUsage: skillUsage,
      chromeExtension: json['chromeExtension'] != null
          ? ChromeExtensionPairing.fromJson(
              json['chromeExtension'] as Map<String, dynamic>,
            )
          : null,
      neomClawHints: json['neomClawHints'] != null
          ? NeomClawHints.fromJson(
              json['neomClawHints'] as Map<String, dynamic>,
            )
          : null,
      feedbackSurveyState: json['feedbackSurveyState'] != null
          ? FeedbackSurveyState.fromJson(
              json['feedbackSurveyState'] as Map<String, dynamic>,
            )
          : null,
      firstStartTime: json['firstStartTime'] as String?,
      remoteDialogSeen: json['remoteDialogSeen'] as bool?,
      lastPlanModeUse: json['lastPlanModeUse'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (apiKeyHelper != null) map['apiKeyHelper'] = apiKeyHelper;
    if (projects != null) {
      map['projects'] = projects!.map((k, v) => MapEntry(k, v.toJson()));
    }
    map['numStartups'] = numStartups;
    if (installMethod != null) map['installMethod'] = installMethod!.name;
    if (autoUpdates != null) map['autoUpdates'] = autoUpdates;
    if (userID != null) map['userID'] = userID;
    map['theme'] = theme.name;
    if (hasCompletedOnboarding != null) {
      map['hasCompletedOnboarding'] = hasCompletedOnboarding;
    }
    map['preferredNotifChannel'] = preferredNotifChannel.name;
    map['verbose'] = verbose;
    if (primaryApiKey != null) map['primaryApiKey'] = primaryApiKey;
    if (oauthAccount != null) map['oauthAccount'] = oauthAccount!.toJson();
    map['editorMode'] = editorMode.name;
    map['autoCompactEnabled'] = autoCompactEnabled;
    map['showTurnDuration'] = showTurnDuration;
    if (env.isNotEmpty) map['env'] = env;
    map['diffTool'] = diffTool.name;
    if (tipsHistory.isNotEmpty) map['tipsHistory'] = tipsHistory;
    map['memoryUsageCount'] = memoryUsageCount;
    map['todoFeatureEnabled'] = todoFeatureEnabled;
    map['messageIdleNotifThresholdMs'] = messageIdleNotifThresholdMs;
    map['fileCheckpointingEnabled'] = fileCheckpointingEnabled;
    map['terminalProgressBarEnabled'] = terminalProgressBarEnabled;
    if (cachedStatsigGates.isNotEmpty) {
      map['cachedStatsigGates'] = cachedStatsigGates;
    }
    map['respectGitignore'] = respectGitignore;
    map['copyFullResponse'] = copyFullResponse;
    if (remoteControlAtStartup != null) {
      map['remoteControlAtStartup'] = remoteControlAtStartup;
    }
    if (migrationVersion != null) map['migrationVersion'] = migrationVersion;
    if (firstStartTime != null) map['firstStartTime'] = firstStartTime;
    return map;
  }
}

// ---------------------------------------------------------------------------
// Enum parsers
// ---------------------------------------------------------------------------

InstallMethod? _parseInstallMethod(String? v) => switch (v) {
  'local' => InstallMethod.local,
  'native' => InstallMethod.native,
  'global' => InstallMethod.global,
  _ => v != null ? InstallMethod.unknown : null,
};

ThemeSetting _parseTheme(String? v) => switch (v) {
  'light' => ThemeSetting.light,
  'lightHighContrast' => ThemeSetting.lightHighContrast,
  'darkHighContrast' => ThemeSetting.darkHighContrast,
  _ => ThemeSetting.dark,
};

NotificationChannel _parseNotifChannel(String? v) => switch (v) {
  'iterm2' => NotificationChannel.iterm2,
  'terminal_bell' => NotificationChannel.terminalBell,
  'terminal_notifier' => NotificationChannel.terminalNotifier,
  'applescript' => NotificationChannel.applescript,
  'native' => NotificationChannel.native,
  'none' => NotificationChannel.none,
  _ => NotificationChannel.auto,
};

EditorMode _parseEditorMode(String? v) => switch (v) {
  'vim' => EditorMode.vim,
  'emacs' => EditorMode.emacs,
  _ => EditorMode.normal,
};

DiffTool _parseDiffTool(String? v) => switch (v) {
  'terminal' => DiffTool.terminal,
  _ => DiffTool.auto,
};

// ---------------------------------------------------------------------------
// Config key lists
// ---------------------------------------------------------------------------

const List<String> globalConfigKeys = [
  'apiKeyHelper',
  'installMethod',
  'autoUpdates',
  'autoUpdatesProtectedForNative',
  'theme',
  'verbose',
  'preferredNotifChannel',
  'shiftEnterKeyBindingInstalled',
  'editorMode',
  'hasUsedBackslashReturn',
  'autoCompactEnabled',
  'showTurnDuration',
  'diffTool',
  'env',
  'tipsHistory',
  'todoFeatureEnabled',
  'showExpandedTodos',
  'messageIdleNotifThresholdMs',
  'autoConnectIde',
  'autoInstallIdeExtension',
  'fileCheckpointingEnabled',
  'terminalProgressBarEnabled',
  'showStatusInTerminalTab',
  'taskCompleteNotifEnabled',
  'inputNeededNotifEnabled',
  'agentPushNotifEnabled',
  'respectGitignore',
  'neomClawInChromeDefaultEnabled',
  'hasCompletedNeomClawInChromeOnboarding',
  'lspRecommendationDisabled',
  'copyFullResponse',
  'copyOnSelect',
  'permissionExplainerEnabled',
  'prStatusFooterEnabled',
  'remoteControlAtStartup',
  'remoteDialogSeen',
];

bool isGlobalConfigKey(String key) => globalConfigKeys.contains(key);

const List<String> projectConfigKeys = [
  'allowedTools',
  'hasTrustDialogAccepted',
  'hasCompletedProjectOnboarding',
];

bool isProjectConfigKey(String key) => projectConfigKeys.contains(key);

// ---------------------------------------------------------------------------
// ConfigParseError
// ---------------------------------------------------------------------------

class ConfigParseError implements Exception {
  final String message;
  final String filePath;

  ConfigParseError(this.message, this.filePath);

  @override
  String toString() => 'ConfigParseError($filePath): $message';
}

// ---------------------------------------------------------------------------
// ConfigController — Sint-based reactive config manager
// ---------------------------------------------------------------------------

class ConfigController extends SintController {
  ConfigController({
    required this.configFilePath,
    required this.cwd,
    String? configHomeDir,
  }) : _configHomeDir = configHomeDir;

  final String configFilePath;
  final String cwd;
  final String? _configHomeDir;

  // Reactive state
  late final globalConfig = GlobalConfig.defaults().obs;
  late final currentProjectConfig = ProjectConfig.defaultConfig().obs;
  final configWriteCount = 0.obs;

  // Cache
  int _cacheMtime = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  // ignore: unused_field
  final bool _insideGetConfig = false;
  bool _configReadingAllowed = false;
  bool _trustAccepted = false;
  String? _projectPath;
  Timer? _freshnessWatcher;

  static const _minBackupIntervalMs = 60000;
  static const _maxBackups = 5;
  static const _freshnessPollMs = 1000;
  static const _lockTimeoutMs = 5 * 60 * 1000;
  static const configWriteDisplayThreshold = 20;

  // ---------------------------------------------------------------------------
  // Paths
  // ---------------------------------------------------------------------------

  String get configHomeDir =>
      _configHomeDir ??
      (() {
        final xdg = Platform.environment['XDG_CONFIG_HOME'];
        if (xdg != null && xdg.isNotEmpty) return p.join(xdg, 'neomclaw');
        final home =
            Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '';
        return p.join(home, '.neomclaw');
      })();

  String get _configBackupDir => p.join(configHomeDir, 'backups');

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onClose() {
    stopFreshnessWatcher();
    super.onClose();
  }

  // ---------------------------------------------------------------------------
  // Enable configs (must be called before reading)
  // ---------------------------------------------------------------------------

  void enableConfigs() {
    if (_configReadingAllowed) return;
    _configReadingAllowed = true;
    _readConfigFromDisk(throwOnInvalid: true);
  }

  // ---------------------------------------------------------------------------
  // Get global config (cached)
  // ---------------------------------------------------------------------------

  GlobalConfig getGlobalConfig() {
    if (_cacheMtime > 0) {
      _cacheHits++;
      return globalConfig.value;
    }

    _cacheMisses++;
    try {
      int? mtimeMs;
      try {
        final stat = File(configFilePath).statSync();
        mtimeMs = stat.modified.millisecondsSinceEpoch;
      } catch (_) {}

      final config = _migrateConfigFields(_readConfigFromDisk());
      globalConfig.value = config;
      _cacheMtime = mtimeMs ?? DateTime.now().millisecondsSinceEpoch;
      _startFreshnessWatcher();
      return config;
    } catch (_) {
      return _migrateConfigFields(_readConfigFromDisk());
    }
  }

  // ---------------------------------------------------------------------------
  // Get current project config
  // ---------------------------------------------------------------------------

  ProjectConfig getCurrentProjectConfig() {
    final path = getProjectPathForConfig();
    final config = getGlobalConfig();
    if (config.projects == null) return ProjectConfig.defaultConfig();

    final pc = config.projects![path];
    if (pc == null) return ProjectConfig.defaultConfig();

    // Fix allowedTools if it was somehow a string
    return pc;
  }

  // ---------------------------------------------------------------------------
  // Project path for config lookup (memoized)
  // ---------------------------------------------------------------------------

  String getProjectPathForConfig() {
    if (_projectPath != null) return _projectPath!;
    final gitRoot = _findCanonicalGitRoot(cwd);
    _projectPath = _normalizePathForConfigKey(gitRoot ?? p.canonicalize(cwd));
    return _projectPath!;
  }

  // ---------------------------------------------------------------------------
  // Save global config
  // ---------------------------------------------------------------------------

  void saveGlobalConfig(GlobalConfig Function(GlobalConfig current) updater) {
    final didWrite = _saveConfigWithLock((current) {
      final config = updater(current);
      if (identical(config, current)) return current;
      // Remove project history during save
      _removeProjectHistory(config);
      return config;
    });

    if (didWrite) {
      _writeThroughCache(globalConfig.value);
    }
  }

  // ---------------------------------------------------------------------------
  // Save current project config
  // ---------------------------------------------------------------------------

  void saveCurrentProjectConfig(
    ProjectConfig Function(ProjectConfig current) updater,
  ) {
    final path = getProjectPathForConfig();

    final didWrite = _saveConfigWithLock((current) {
      final currentPc =
          current.projects?[path] ?? ProjectConfig.defaultConfig();
      final newPc = updater(currentPc);
      if (identical(newPc, currentPc)) return current;

      final updatedProjects = Map<String, ProjectConfig>.from(
        current.projects ?? {},
      );
      updatedProjects[path] = newPc;
      current.projects = updatedProjects;
      return current;
    });

    if (didWrite) {
      _writeThroughCache(globalConfig.value);
    }
  }

  // ---------------------------------------------------------------------------
  // Trust dialog
  // ---------------------------------------------------------------------------

  bool checkHasTrustDialogAccepted({bool sessionTrustAccepted = false}) {
    if (_trustAccepted) return true;
    final accepted = _computeTrustDialogAccepted(
      sessionTrustAccepted: sessionTrustAccepted,
    );
    if (accepted) _trustAccepted = true;
    return accepted;
  }

  void resetTrustDialogAcceptedCache() {
    _trustAccepted = false;
  }

  bool _computeTrustDialogAccepted({required bool sessionTrustAccepted}) {
    if (sessionTrustAccepted) return true;

    final config = getGlobalConfig();
    final projectPath = getProjectPathForConfig();
    if (config.projects?[projectPath]?.hasTrustDialogAccepted == true) {
      return true;
    }

    var currentPath = _normalizePathForConfigKey(cwd);
    while (true) {
      if (config.projects?[currentPath]?.hasTrustDialogAccepted == true) {
        return true;
      }
      final parentPath = _normalizePathForConfigKey(
        p.canonicalize(p.join(currentPath, '..')),
      );
      if (parentPath == currentPath) break;
      currentPath = parentPath;
    }
    return false;
  }

  bool isPathTrusted(String dir) {
    final config = getGlobalConfig();
    var currentPath = _normalizePathForConfigKey(p.canonicalize(dir));
    while (true) {
      if (config.projects?[currentPath]?.hasTrustDialogAccepted == true) {
        return true;
      }
      final parentPath = _normalizePathForConfigKey(
        p.canonicalize(p.join(currentPath, '..')),
      );
      if (parentPath == currentPath) return false;
      currentPath = parentPath;
    }
  }

  // ---------------------------------------------------------------------------
  // Custom API key status
  // ---------------------------------------------------------------------------

  String getCustomApiKeyStatus(String truncatedApiKey) {
    final config = getGlobalConfig();
    final responses = config.customApiKeyResponses;
    if (responses == null) return 'new';

    final approved = (responses['approved'] as List?)?.cast<String>();
    final rejected = (responses['rejected'] as List?)?.cast<String>();
    if (approved?.contains(truncatedApiKey) == true) return 'approved';
    if (rejected?.contains(truncatedApiKey) == true) return 'rejected';
    return 'new';
  }

  // ---------------------------------------------------------------------------
  // Auto updater
  // ---------------------------------------------------------------------------

  AutoUpdaterDisabledReason? getAutoUpdaterDisabledReason() {
    final envMap = Platform.environment;
    if (envMap['NODE_ENV'] == 'development') {
      return const AutoUpdaterDisabledDevelopment();
    }
    if (_isEnvTruthy(envMap['DISABLE_AUTOUPDATER'])) {
      return const AutoUpdaterDisabledEnv(envVar: 'DISABLE_AUTOUPDATER');
    }
    final essentialReason = _getEssentialTrafficOnlyReason(envMap);
    if (essentialReason != null) {
      return AutoUpdaterDisabledEnv(envVar: essentialReason);
    }
    final config = getGlobalConfig();
    if (config.autoUpdates == false &&
        (config.installMethod != InstallMethod.native ||
            config.autoUpdatesProtectedForNative != true)) {
      return const AutoUpdaterDisabledConfig();
    }
    return null;
  }

  bool isAutoUpdaterDisabled() => getAutoUpdaterDisabledReason() != null;

  bool shouldSkipPluginAutoupdate() {
    return isAutoUpdaterDisabled() &&
        !_isEnvTruthy(Platform.environment['FORCE_AUTOUPDATE_PLUGINS']);
  }

  // ---------------------------------------------------------------------------
  // User ID / first start
  // ---------------------------------------------------------------------------

  String getOrCreateUserID() {
    final config = getGlobalConfig();
    if (config.userID != null && config.userID!.isNotEmpty) {
      return config.userID!;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final uid = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    saveGlobalConfig((c) {
      c.userID = uid;
      return c;
    });
    return uid;
  }

  void recordFirstStartTime() {
    final config = getGlobalConfig();
    if (config.firstStartTime != null) return;
    final ts = DateTime.now().toIso8601String();
    saveGlobalConfig((c) {
      c.firstStartTime ??= ts;
      return c;
    });
  }

  // ---------------------------------------------------------------------------
  // Memory paths
  // ---------------------------------------------------------------------------

  String getMemoryPath(MemoryType memoryType, {String? managedFilePath}) {
    return switch (memoryType) {
      MemoryType.user => p.join(configHomeDir, 'NEOMCLAW.md'),
      MemoryType.local => p.join(cwd, 'NEOMCLAW.local.md'),
      MemoryType.project => p.join(cwd, 'NEOMCLAW.md'),
      MemoryType.managed => p.join(
        managedFilePath ?? p.join(configHomeDir, 'managed'),
        'NEOMCLAW.md',
      ),
      MemoryType.autoMem => p.join(configHomeDir, 'auto', 'NEOMCLAW.md'),
    };
  }

  String getManagedNeomClawRulesDir({String? managedFilePath}) {
    final base = managedFilePath ?? p.join(configHomeDir, 'managed');
    return p.join(base, '.neomclaw', 'rules');
  }

  String getUserNeomClawRulesDir() => p.join(configHomeDir, 'rules');

  // ---------------------------------------------------------------------------
  // Remote control at startup
  // ---------------------------------------------------------------------------

  bool getRemoteControlAtStartup() {
    final explicit = getGlobalConfig().remoteControlAtStartup;
    if (explicit != null) return explicit;
    return false;
  }

  // ---------------------------------------------------------------------------
  // Cache stats
  // ---------------------------------------------------------------------------

  ({int hits, int misses, double hitRate}) getCacheStats() {
    final total = _cacheHits + _cacheMisses;
    return (
      hits: _cacheHits,
      misses: _cacheMisses,
      hitRate: total > 0 ? _cacheHits / total : 0.0,
    );
  }

  void resetCacheStats() {
    _cacheHits = 0;
    _cacheMisses = 0;
  }

  // ---------------------------------------------------------------------------
  // Private: read config from disk
  // ---------------------------------------------------------------------------

  GlobalConfig _readConfigFromDisk({bool throwOnInvalid = false}) {
    try {
      final content = File(configFilePath).readAsStringSync();
      try {
        final stripped = _stripBOM(content);
        final parsed = jsonDecode(stripped) as Map<String, dynamic>;
        return GlobalConfig.fromJson(parsed);
      } catch (e) {
        if (throwOnInvalid) {
          throw ConfigParseError(e.toString(), configFilePath);
        }
        return GlobalConfig.defaults();
      }
    } catch (e) {
      if (e is ConfigParseError) rethrow;
      if (e is FileSystemException) {
        final backup = _findMostRecentBackup();
        if (backup != null) {
          stderr.writeln(
            '\nConfig file not found at: $configFilePath\n'
            'Backup exists at: $backup\n'
            'Restore with: cp "$backup" "$configFilePath"\n',
          );
        }
      }
      return GlobalConfig.defaults();
    }
  }

  // ---------------------------------------------------------------------------
  // Private: save with lock
  // ---------------------------------------------------------------------------

  bool _saveConfigWithLock(
    GlobalConfig Function(GlobalConfig current) mergeFn,
  ) {
    final lockPath = '$configFilePath.lock';
    bool acquired = false;

    try {
      acquired = _acquireLock(lockPath);
      if (!acquired) {
        // Fallback: unlocked write
        return _saveConfigFallback(mergeFn);
      }

      final current = _readConfigFromDisk();
      if (_wouldLoseAuthState(current)) return false;

      final merged = mergeFn(current);
      if (identical(merged, current)) return false;

      _createBackupIfNeeded();
      _writeConfigToDisk(merged);
      globalConfig.value = merged;
      return true;
    } catch (e) {
      return _saveConfigFallback(mergeFn);
    } finally {
      if (acquired) _releaseLock(lockPath);
    }
  }

  bool _saveConfigFallback(
    GlobalConfig Function(GlobalConfig current) mergeFn,
  ) {
    final current = _readConfigFromDisk();
    if (_wouldLoseAuthState(current)) return false;

    final merged = mergeFn(current);
    if (identical(merged, current)) return false;

    _writeConfigToDisk(merged);
    globalConfig.value = merged;
    return true;
  }

  bool _wouldLoseAuthState(GlobalConfig fresh) {
    final cached = globalConfig.value;
    final lostOauth = cached.oauthAccount != null && fresh.oauthAccount == null;
    final lostOnboarding =
        cached.hasCompletedOnboarding == true &&
        fresh.hasCompletedOnboarding != true;
    return lostOauth || lostOnboarding;
  }

  void _writeConfigToDisk(GlobalConfig config) {
    final dir = Directory(p.dirname(configFilePath));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final encoded = const JsonEncoder.withIndent('  ').convert(config.toJson());
    File(configFilePath).writeAsStringSync(encoded, flush: true);
    configWriteCount.value++;
    _cacheMtime = DateTime.now().millisecondsSinceEpoch;
  }

  void _writeThroughCache(GlobalConfig config) {
    globalConfig.value = config;
    _cacheMtime = DateTime.now().millisecondsSinceEpoch;
  }

  // ---------------------------------------------------------------------------
  // Private: lock management
  // ---------------------------------------------------------------------------

  bool _acquireLock(String lockPath) {
    final lockFile = File(lockPath);
    try {
      if (lockFile.existsSync()) {
        final age = DateTime.now()
            .difference(lockFile.statSync().modified)
            .inMilliseconds;
        if (age < _lockTimeoutMs) return false;
        lockFile.deleteSync();
      }
    } catch (_) {}

    try {
      lockFile.writeAsStringSync('$pid', mode: FileMode.writeOnly, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _releaseLock(String lockPath) {
    try {
      final f = File(lockPath);
      if (f.existsSync() && f.readAsStringSync() == '$pid') f.deleteSync();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Private: backup management
  // ---------------------------------------------------------------------------

  void _createBackupIfNeeded() {
    try {
      final file = File(configFilePath);
      if (!file.existsSync()) return;

      final backupDir = Directory(_configBackupDir);
      if (!backupDir.existsSync()) backupDir.createSync(recursive: true);

      final fileBase = p.basename(configFilePath);
      final existing =
          backupDir
              .listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).startsWith('$fileBase.backup.'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));

      final recentTs = existing.isNotEmpty
          ? int.tryParse(existing.first.path.split('.backup.').last) ?? 0
          : 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - recentTs >= _minBackupIntervalMs) {
        file.copySync(p.join(_configBackupDir, '$fileBase.backup.$now'));
      }

      // Clean up old backups
      final all =
          backupDir
              .listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).startsWith('$fileBase.backup.'))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));

      for (final old in all.skip(_maxBackups)) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  String? _findMostRecentBackup() {
    final fileBase = p.basename(configFilePath);

    try {
      final dir = Directory(_configBackupDir);
      if (dir.existsSync()) {
        final backups =
            dir
                .listSync()
                .whereType<File>()
                .where(
                  (f) => p.basename(f.path).startsWith('$fileBase.backup.'),
                )
                .map((f) => f.path)
                .toList()
              ..sort();
        if (backups.isNotEmpty) return backups.last;
      }
    } catch (_) {}

    // Legacy location
    try {
      final dir = Directory(p.dirname(configFilePath));
      final backups =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).startsWith('$fileBase.backup.'))
              .map((f) => f.path)
              .toList()
            ..sort();
      if (backups.isNotEmpty) return backups.last;

      final legacy = '$configFilePath.backup';
      if (File(legacy).existsSync()) return legacy;
    } catch (_) {}

    return null;
  }

  // ---------------------------------------------------------------------------
  // Private: migration
  // ---------------------------------------------------------------------------

  GlobalConfig _migrateConfigFields(GlobalConfig config) {
    if (config.installMethod != null) return config;
    config.installMethod = InstallMethod.unknown;
    return config;
  }

  void _removeProjectHistory(GlobalConfig config) {
    // No-op in Dart: ProjectConfig never has a history field.
  }

  // ---------------------------------------------------------------------------
  // Private: freshness watcher
  // ---------------------------------------------------------------------------

  void _startFreshnessWatcher() {
    if (_freshnessWatcher != null) return;
    _freshnessWatcher = Timer.periodic(
      const Duration(milliseconds: _freshnessPollMs),
      (_) => _checkFreshness(),
    );
  }

  void stopFreshnessWatcher() {
    _freshnessWatcher?.cancel();
    _freshnessWatcher = null;
  }

  void _checkFreshness() {
    try {
      final stat = File(configFilePath).statSync();
      final mtimeMs = stat.modified.millisecondsSinceEpoch;
      if (mtimeMs > _cacheMtime) {
        final config = _migrateConfigFields(_readConfigFromDisk());
        globalConfig.value = config;
        _cacheMtime = mtimeMs;
      }
    } catch (_) {}
  }

  void invalidateCache() {
    _cacheMtime = 0;
  }

  // ---------------------------------------------------------------------------
  // Private: helpers
  // ---------------------------------------------------------------------------

  static String _normalizePathForConfigKey(String path) =>
      path.replaceAll(r'\', '/');

  static String? _findCanonicalGitRoot(String startDir) {
    var dir = startDir;
    while (true) {
      if (Directory(p.join(dir, '.git')).existsSync()) {
        return p.canonicalize(dir);
      }
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
  }

  static String _stripBOM(String content) {
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      return content.substring(1);
    }
    return content;
  }

  static bool _isEnvTruthy(String? value) {
    if (value == null) return false;
    return const ['1', 'true', 'yes'].contains(value.toLowerCase());
  }

  static String? _getEssentialTrafficOnlyReason(Map<String, String> env) {
    if (_isEnvTruthy(env['NEOMCLAW_ESSENTIAL_TRAFFIC_ONLY'])) {
      return 'NEOMCLAW_ESSENTIAL_TRAFFIC_ONLY';
    }
    if (_isEnvTruthy(env['NEOMCLAW_DISABLE_NONESSENTIAL_TRAFFIC'])) {
      return 'NEOMCLAW_DISABLE_NONESSENTIAL_TRAFFIC';
    }
    return null;
  }
}
