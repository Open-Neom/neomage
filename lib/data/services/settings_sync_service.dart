// Settings sync service — port of neomage/src/services/settingsSync/.
// Syncs user settings and memory files across Neomage environments.
//
// - Interactive CLI: Uploads local settings to remote (incremental, only changed entries)
// - CCR: Downloads remote settings to local before plugin installation
//
// Backend API: anthropic/anthropic#218817

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:sint/sint.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Types (Zod schemas ported to Dart classes)
// ═══════════════════════════════════════════════════════════════════════════

/// Content portion of user sync data — flat key-value storage.
/// Keys are opaque strings (typically file paths).
/// Values are UTF-8 string content (JSON, Markdown, etc).
class UserSyncContent {
  final Map<String, String> entries;

  const UserSyncContent({required this.entries});

  factory UserSyncContent.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as Map<String, dynamic>?;
    return UserSyncContent(
      entries: rawEntries?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {'entries': entries};
}

/// Full response from GET /api/neomage/user_settings.
class UserSyncData {
  final String userId;
  final int version;
  final String lastModified;
  final String checksum;
  final UserSyncContent content;

  const UserSyncData({
    required this.userId,
    required this.version,
    required this.lastModified,
    required this.checksum,
    required this.content,
  });

  factory UserSyncData.fromJson(Map<String, dynamic> json) {
    return UserSyncData(
      userId: json['userId'] as String? ?? '',
      version: json['version'] as int? ?? 0,
      lastModified: json['lastModified'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
      content: UserSyncContent.fromJson(
        json['content'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'version': version,
    'lastModified': lastModified,
    'checksum': checksum,
    'content': content.toJson(),
  };
}

/// Result from fetching user settings.
class SettingsSyncFetchResult {
  final bool success;
  final UserSyncData? data;
  final bool isEmpty;
  final String? error;
  final bool skipRetry;

  const SettingsSyncFetchResult({
    required this.success,
    this.data,
    this.isEmpty = false,
    this.error,
    this.skipRetry = false,
  });
}

/// Result from uploading user settings.
class SettingsSyncUploadResult {
  final bool success;
  final String? checksum;
  final String? lastModified;
  final String? error;

  const SettingsSyncUploadResult({
    required this.success,
    this.checksum,
    this.lastModified,
    this.error,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Sync keys
// ═══════════════════════════════════════════════════════════════════════════

/// Keys used for sync entries — mirrors the TS SYNC_KEYS constant.
class SyncKeys {
  static const userSettings = '~/.neomage/settings.json';
  static const userMemory = '~/.neomage/NEOMAGE.md';

  static String projectSettings(String projectId) =>
      'projects/$projectId/.neomage/settings.local.json';

  static String projectMemory(String projectId) =>
      'projects/$projectId/NEOMAGE.local.md';
}

// ═══════════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════════

const _defaultMaxRetries = 3;
const _maxFileSizeBytes = 500 * 1024; // 500 KB per file

// ═══════════════════════════════════════════════════════════════════════════
// Axios error classification (simplified port)
// ═══════════════════════════════════════════════════════════════════════════

/// Classified HTTP error.
class ClassifiedError {
  final String kind; // 'auth', 'timeout', 'network', 'other'
  final String message;

  const ClassifiedError({required this.kind, required this.message});
}

/// Classify an HTTP error into a category.
ClassifiedError classifyHttpError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('401') ||
      msg.contains('403') ||
      msg.contains('unauthorized')) {
    return ClassifiedError(
      kind: 'auth',
      message: 'Not authorized for settings sync',
    );
  }
  if (msg.contains('timeout')) {
    return ClassifiedError(
      kind: 'timeout',
      message: 'Settings sync request timeout',
    );
  }
  if (msg.contains('socket') ||
      msg.contains('connection') ||
      msg.contains('network')) {
    return ClassifiedError(
      kind: 'network',
      message: 'Cannot connect to server',
    );
  }
  return ClassifiedError(kind: 'other', message: error.toString());
}

/// Compute retry delay with exponential backoff.
int getRetryDelay(int attempt) {
  // Exponential backoff: 1s, 2s, 4s, ...
  return 1000 * (1 << (attempt - 1));
}

// ═══════════════════════════════════════════════════════════════════════════
// Settings sync service
// ═══════════════════════════════════════════════════════════════════════════

/// Settings sync service controller.
///
/// Syncs user settings and memory files between local disk and the
/// Anthropic API backend. Supports both upload (interactive CLI) and
/// download (CCR mode) patterns.
class SettingsSyncController extends SintController {
  // ── Dependencies ────────────────────────────────────────────────────

  /// Whether the user is authenticated with first-party OAuth.
  final bool Function() isUsingOAuth;

  /// Whether the current session is interactive.
  final bool Function() isInteractive;

  /// Feature gate for upload.
  final bool Function() isUploadFeatureEnabled;

  /// Feature gate for download.
  final bool Function() isDownloadFeatureEnabled;

  /// GrowthBook cached feature value for upload gate.
  final bool Function() isUploadGateEnabled;

  /// GrowthBook cached feature value for download gate.
  final bool Function() isDownloadGateEnabled;

  /// Get the API provider type.
  final String Function() getApiProvider;

  /// Check if the base URL is first-party Anthropic.
  final bool Function() isFirstPartyBaseUrl;

  /// Get OAuth tokens.
  final ({String? accessToken, List<String>? scopes})? Function()
  getOAuthTokens;

  /// Check and refresh OAuth token if needed.
  final Future<void> Function() checkAndRefreshOAuthToken;

  /// Get git repo remote hash for project identification.
  final Future<String?> Function() getRepoRemoteHash;

  /// HTTP GET.
  final Future<({int statusCode, Map<String, dynamic>? data})> Function(
    String url,
    Map<String, String> headers,
  )
  httpGet;

  /// HTTP PUT.
  final Future<({int statusCode, Map<String, dynamic>? data})> Function(
    String url,
    Object body,
    Map<String, String> headers,
  )
  httpPut;

  /// Get user agent string.
  final String Function() getUserAgent;

  /// Get base API URL for endpoint construction.
  final String Function() getBaseApiUrl;

  /// Get beta header for OAuth.
  final String Function() getBetaHeader;

  // ── File system helpers ─────────────────────────────────────────────

  /// Get settings file path for a source key.
  final String? Function(String source) getSettingsFilePath;

  /// Get memory file path for scope.
  final String Function(String scope) getMemoryPath;

  /// Read a file. Returns null if not found.
  final Future<String?> Function(String path) readFileOrNull;

  /// Write a file (creates parent dirs).
  final Future<bool> Function(String path, String content) writeFileSafe;

  /// Get file size in bytes.
  final Future<int?> Function(String path) getFileSize;

  /// Reset settings cache after writing.
  final void Function() resetSettingsCache;

  /// Clear memory file caches.
  final void Function() clearMemoryFileCaches;

  /// Mark a file write as internal (suppress change detection).
  final void Function(String path) markInternalWrite;

  /// Diagnostics logger.
  final void Function(String level, String event, [Map<String, Object?>? data])
  logDiagnostics;

  /// Analytics event logger.
  final void Function(String eventName, Map<String, Object?> metadata) logEvent;

  // ── State ───────────────────────────────────────────────────────────

  /// Cached download promise for deduplication.
  Completer<bool>? _downloadCompleter;

  SettingsSyncController({
    required this.isUsingOAuth,
    required this.isInteractive,
    required this.isUploadFeatureEnabled,
    required this.isDownloadFeatureEnabled,
    required this.isUploadGateEnabled,
    required this.isDownloadGateEnabled,
    required this.getApiProvider,
    required this.isFirstPartyBaseUrl,
    required this.getOAuthTokens,
    required this.checkAndRefreshOAuthToken,
    required this.getRepoRemoteHash,
    required this.httpGet,
    required this.httpPut,
    required this.getUserAgent,
    required this.getBaseApiUrl,
    required this.getBetaHeader,
    required this.getSettingsFilePath,
    required this.getMemoryPath,
    required this.readFileOrNull,
    required this.writeFileSafe,
    required this.getFileSize,
    required this.resetSettingsCache,
    required this.clearMemoryFileCaches,
    required this.markInternalWrite,
    required this.logDiagnostics,
    required this.logEvent,
  });

  // ── Public API ──────────────────────────────────────────────────────

  /// Upload local settings to remote (interactive CLI only).
  /// Called from preAction. Runs in background — caller should not await.
  Future<void> uploadUserSettingsInBackground() async {
    try {
      if (!isUploadFeatureEnabled() ||
          !isUploadGateEnabled() ||
          !isInteractive() ||
          !_isUsingOAuthInternal()) {
        logDiagnostics('info', 'settings_sync_upload_skipped');
        logEvent('tengu_settings_sync_upload_skipped_ineligible', {});
        return;
      }

      logDiagnostics('info', 'settings_sync_upload_starting');
      final result = await _fetchUserSettings();
      if (!result.success) {
        logDiagnostics('warn', 'settings_sync_upload_fetch_failed');
        logEvent('tengu_settings_sync_upload_fetch_failed', {});
        return;
      }

      final projectId = await getRepoRemoteHash();
      final localEntries = await _buildEntriesFromLocalFiles(projectId);
      final remoteEntries = result.isEmpty
          ? <String, String>{}
          : result.data!.content.entries;

      final changedEntries = <String, String>{};
      for (final entry in localEntries.entries) {
        if (remoteEntries[entry.key] != entry.value) {
          changedEntries[entry.key] = entry.value;
        }
      }

      final entryCount = changedEntries.length;
      if (entryCount == 0) {
        logDiagnostics('info', 'settings_sync_upload_no_changes');
        logEvent('tengu_settings_sync_upload_skipped', {});
        return;
      }

      final uploadResult = await _uploadUserSettings(changedEntries);
      if (uploadResult.success) {
        logDiagnostics('info', 'settings_sync_upload_success');
        logEvent('tengu_settings_sync_upload_success', {
          'entryCount': entryCount,
        });
      } else {
        logDiagnostics('warn', 'settings_sync_upload_failed');
        logEvent('tengu_settings_sync_upload_failed', {
          'entryCount': entryCount,
        });
      }
    } catch (_) {
      logDiagnostics('error', 'settings_sync_unexpected_error');
    }
  }

  /// Download settings from remote for CCR mode.
  /// First call starts the fetch; subsequent calls join it.
  Future<bool> downloadUserSettings() {
    if (_downloadCompleter != null) return _downloadCompleter!.future;
    _downloadCompleter = Completer<bool>();
    _doDownloadUserSettings().then(
      (result) => _downloadCompleter!.complete(result),
      onError: (e) => _downloadCompleter!.complete(false),
    );
    return _downloadCompleter!.future;
  }

  /// Force a fresh download, bypassing the cached startup promise.
  Future<bool> redownloadUserSettings() {
    _downloadCompleter = Completer<bool>();
    _doDownloadUserSettings(0).then(
      (result) => _downloadCompleter!.complete(result),
      onError: (e) => _downloadCompleter!.complete(false),
    );
    return _downloadCompleter!.future;
  }

  /// Reset the download promise (for testing).
  void resetDownloadPromiseForTesting() {
    _downloadCompleter = null;
  }

  // ── Private ─────────────────────────────────────────────────────────

  bool _isUsingOAuthInternal() {
    if (getApiProvider() != 'firstParty' || !isFirstPartyBaseUrl()) {
      return false;
    }
    final tokens = getOAuthTokens();
    return tokens != null &&
        tokens.accessToken != null &&
        tokens.accessToken!.isNotEmpty &&
        (tokens.scopes?.contains('user:inference') ?? false);
  }

  String _getEndpoint() => '${getBaseApiUrl()}/api/neomage/user_settings';

  Map<String, String> _getAuthHeaders() {
    final tokens = getOAuthTokens();
    if (tokens?.accessToken != null && tokens!.accessToken!.isNotEmpty) {
      return {
        'Authorization': 'Bearer ${tokens.accessToken}',
        'anthropic-beta': getBetaHeader(),
      };
    }
    return {};
  }

  Future<SettingsSyncFetchResult> _fetchUserSettingsOnce() async {
    try {
      await checkAndRefreshOAuthToken();

      final authHeaders = _getAuthHeaders();
      if (authHeaders.isEmpty) {
        return const SettingsSyncFetchResult(
          success: false,
          error: 'No OAuth token available',
          skipRetry: true,
        );
      }

      final headers = <String, String>{
        ...authHeaders,
        'User-Agent': getUserAgent(),
      };

      final response = await httpGet(_getEndpoint(), headers);

      if (response.statusCode == 404) {
        logDiagnostics('info', 'settings_sync_fetch_empty');
        return const SettingsSyncFetchResult(success: true, isEmpty: true);
      }

      if (response.statusCode != 200 || response.data == null) {
        return SettingsSyncFetchResult(
          success: false,
          error: 'HTTP ${response.statusCode}',
        );
      }

      try {
        final parsed = UserSyncData.fromJson(response.data!);
        logDiagnostics('info', 'settings_sync_fetch_success');
        return SettingsSyncFetchResult(success: true, data: parsed);
      } catch (_) {
        logDiagnostics('warn', 'settings_sync_fetch_invalid_format');
        return const SettingsSyncFetchResult(
          success: false,
          error: 'Invalid settings sync response format',
        );
      }
    } catch (error) {
      final classified = classifyHttpError(error);
      switch (classified.kind) {
        case 'auth':
          return SettingsSyncFetchResult(
            success: false,
            error: classified.message,
            skipRetry: true,
          );
        case 'timeout':
          return SettingsSyncFetchResult(
            success: false,
            error: classified.message,
          );
        case 'network':
          return SettingsSyncFetchResult(
            success: false,
            error: classified.message,
          );
        default:
          return SettingsSyncFetchResult(
            success: false,
            error: classified.message,
          );
      }
    }
  }

  Future<SettingsSyncFetchResult> _fetchUserSettings([
    int maxRetries = _defaultMaxRetries,
  ]) async {
    SettingsSyncFetchResult? lastResult;

    for (var attempt = 1; attempt <= maxRetries + 1; attempt++) {
      lastResult = await _fetchUserSettingsOnce();

      if (lastResult.success) return lastResult;
      if (lastResult.skipRetry) return lastResult;
      if (attempt > maxRetries) return lastResult;

      final delayMs = getRetryDelay(attempt);
      logDiagnostics('info', 'settings_sync_retry', {
        'attempt': attempt,
        'maxRetries': maxRetries,
        'delayMs': delayMs,
      });
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    return lastResult!;
  }

  Future<SettingsSyncUploadResult> _uploadUserSettings(
    Map<String, String> entries,
  ) async {
    try {
      await checkAndRefreshOAuthToken();

      final authHeaders = _getAuthHeaders();
      if (authHeaders.isEmpty) {
        return const SettingsSyncUploadResult(
          success: false,
          error: 'No OAuth token available',
        );
      }

      final headers = <String, String>{
        ...authHeaders,
        'User-Agent': getUserAgent(),
        'Content-Type': 'application/json',
      };

      final response = await httpPut(_getEndpoint(), {
        'entries': entries,
      }, headers);

      logDiagnostics('info', 'settings_sync_uploaded', {
        'entryCount': entries.length,
      });

      return SettingsSyncUploadResult(
        success: true,
        checksum: response.data?['checksum'] as String?,
        lastModified: response.data?['lastModified'] as String?,
      );
    } catch (error) {
      logDiagnostics('warn', 'settings_sync_upload_error');
      return SettingsSyncUploadResult(success: false, error: error.toString());
    }
  }

  /// Try to read a file for sync, with size limit and error handling.
  Future<String?> _tryReadFileForSync(String filePath) async {
    try {
      final size = await getFileSize(filePath);
      if (size == null || size > _maxFileSizeBytes) {
        if (size != null && size > _maxFileSizeBytes) {
          logDiagnostics('info', 'settings_sync_file_too_large');
        }
        return null;
      }

      final content = await readFileOrNull(filePath);
      if (content == null || content.trim().isEmpty) return null;
      return content;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _buildEntriesFromLocalFiles(
    String? projectId,
  ) async {
    final entries = <String, String>{};

    // Global user settings.
    final userSettingsPath = getSettingsFilePath('userSettings');
    if (userSettingsPath != null) {
      final content = await _tryReadFileForSync(userSettingsPath);
      if (content != null) {
        entries[SyncKeys.userSettings] = content;
      }
    }

    // Global user memory.
    final userMemoryPath = getMemoryPath('User');
    final userMemoryContent = await _tryReadFileForSync(userMemoryPath);
    if (userMemoryContent != null) {
      entries[SyncKeys.userMemory] = userMemoryContent;
    }

    // Project-specific files (only if we have a project ID).
    if (projectId != null) {
      final localSettingsPath = getSettingsFilePath('localSettings');
      if (localSettingsPath != null) {
        final content = await _tryReadFileForSync(localSettingsPath);
        if (content != null) {
          entries[SyncKeys.projectSettings(projectId)] = content;
        }
      }

      final localMemoryPath = getMemoryPath('Local');
      final localMemoryContent = await _tryReadFileForSync(localMemoryPath);
      if (localMemoryContent != null) {
        entries[SyncKeys.projectMemory(projectId)] = localMemoryContent;
      }
    }

    return entries;
  }

  Future<bool> _doDownloadUserSettings([
    int maxRetries = _defaultMaxRetries,
  ]) async {
    if (!isDownloadFeatureEnabled()) return false;

    try {
      if (!isDownloadGateEnabled() || !_isUsingOAuthInternal()) {
        logDiagnostics('info', 'settings_sync_download_skipped');
        logEvent('tengu_settings_sync_download_skipped', {});
        return false;
      }

      logDiagnostics('info', 'settings_sync_download_starting');
      final result = await _fetchUserSettings(maxRetries);
      if (!result.success) {
        logDiagnostics('warn', 'settings_sync_download_fetch_failed');
        logEvent('tengu_settings_sync_download_fetch_failed', {});
        return false;
      }

      if (result.isEmpty) {
        logDiagnostics('info', 'settings_sync_download_empty');
        logEvent('tengu_settings_sync_download_empty', {});
        return false;
      }

      final entries = result.data!.content.entries;
      final projectId = await getRepoRemoteHash();
      final entryCount = entries.length;
      logDiagnostics('info', 'settings_sync_download_applying', {
        'entryCount': entryCount,
      });
      await _applyRemoteEntriesToLocal(entries, projectId);
      logEvent('tengu_settings_sync_download_success', {
        'entryCount': entryCount,
      });
      return true;
    } catch (_) {
      logDiagnostics('error', 'settings_sync_download_error');
      logEvent('tengu_settings_sync_download_error', {});
      return false;
    }
  }

  /// Apply remote entries to local files (CCR pull pattern).
  Future<void> _applyRemoteEntriesToLocal(
    Map<String, String> entries,
    String? projectId,
  ) async {
    var appliedCount = 0;
    var settingsWritten = false;
    var memoryWritten = false;

    bool exceedsSizeLimit(String content) {
      final sizeBytes = utf8.encode(content).length;
      if (sizeBytes > _maxFileSizeBytes) {
        logDiagnostics('info', 'settings_sync_file_too_large', {
          'sizeBytes': sizeBytes,
          'maxBytes': _maxFileSizeBytes,
        });
        return true;
      }
      return false;
    }

    // Apply global user settings.
    final userSettingsContent = entries[SyncKeys.userSettings];
    if (userSettingsContent != null) {
      final path = getSettingsFilePath('userSettings');
      if (path != null && !exceedsSizeLimit(userSettingsContent)) {
        markInternalWrite(path);
        if (await writeFileSafe(path, userSettingsContent)) {
          appliedCount++;
          settingsWritten = true;
        }
      }
    }

    // Apply global user memory.
    final userMemoryContent = entries[SyncKeys.userMemory];
    if (userMemoryContent != null) {
      final path = getMemoryPath('User');
      if (!exceedsSizeLimit(userMemoryContent)) {
        if (await writeFileSafe(path, userMemoryContent)) {
          appliedCount++;
          memoryWritten = true;
        }
      }
    }

    // Apply project-specific files.
    if (projectId != null) {
      final projectSettingsKey = SyncKeys.projectSettings(projectId);
      final projectSettingsContent = entries[projectSettingsKey];
      if (projectSettingsContent != null) {
        final path = getSettingsFilePath('localSettings');
        if (path != null && !exceedsSizeLimit(projectSettingsContent)) {
          markInternalWrite(path);
          if (await writeFileSafe(path, projectSettingsContent)) {
            appliedCount++;
            settingsWritten = true;
          }
        }
      }

      final projectMemoryKey = SyncKeys.projectMemory(projectId);
      final projectMemoryContent = entries[projectMemoryKey];
      if (projectMemoryContent != null) {
        final path = getMemoryPath('Local');
        if (!exceedsSizeLimit(projectMemoryContent)) {
          if (await writeFileSafe(path, projectMemoryContent)) {
            appliedCount++;
            memoryWritten = true;
          }
        }
      }
    }

    // Invalidate caches.
    if (settingsWritten) resetSettingsCache();
    if (memoryWritten) clearMemoryFileCaches();

    logDiagnostics('info', 'settings_sync_applied', {
      'appliedCount': appliedCount,
    });
  }
}
