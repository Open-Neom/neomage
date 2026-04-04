/// Release notes, auto-updater, semantic versioning, and user management
/// utilities.
///
/// Ported from:
///   - releaseNotes.ts (360 LOC) -- changelog fetching, parsing, display
///   - autoUpdater.ts (561 LOC) -- version checking, lock management, install
///   - semver.ts (59 LOC) -- semantic version comparison
///   - user.ts (194 LOC) -- user data and email resolution
library;

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:sint/sint.dart';

// ===========================================================================
// Semver (ported from semver.ts)
// ===========================================================================

/// Parsed semantic version for comparison.
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;
  final String? buildMetadata;

  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease,
    this.buildMetadata,
  });

  /// Parse a version string into a SemVer.
  ///
  /// Supports formats like "1.2.3", "1.2.3-beta.1", "1.2.3+sha123".
  /// Returns null if the string cannot be parsed.
  static SemVer? tryParse(String version) {
    // Coerce: strip leading non-numeric characters (like 'v')
    var v = version.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }

    // Split off build metadata
    String? build;
    final plusIdx = v.indexOf('+');
    if (plusIdx >= 0) {
      build = v.substring(plusIdx + 1);
      v = v.substring(0, plusIdx);
    }

    // Split off pre-release
    String? pre;
    final dashIdx = v.indexOf('-');
    if (dashIdx >= 0) {
      pre = v.substring(dashIdx + 1);
      v = v.substring(0, dashIdx);
    }

    final parts = v.split('.');
    if (parts.length < 3) {
      // Try to coerce: pad missing parts with 0
      while (parts.length < 3) {
        parts.add('0');
      }
    }

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);

    if (major == null || minor == null || patch == null) return null;

    return SemVer(
      major: major,
      minor: minor,
      patch: patch,
      preRelease: pre,
      buildMetadata: build,
    );
  }

  /// Parse a version string, throwing if it cannot be parsed.
  factory SemVer.parse(String version) {
    final result = tryParse(version);
    if (result == null) {
      throw FormatException('Invalid semver: $version');
    }
    return result;
  }

  /// The base version string without build metadata (for display).
  String get version {
    final base = '$major.$minor.$patch';
    if (preRelease != null) return '$base-$preRelease';
    return base;
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Pre-release versions have lower precedence than release
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease != null) {
      return preRelease!.compareTo(other.preRelease!);
    }

    return 0; // Build metadata is ignored in comparison per SemVer spec
  }

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    final pre = preRelease != null ? '-$preRelease' : '';
    final build = buildMetadata != null ? '+$buildMetadata' : '';
    return '$base$pre$build';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);
}

/// Returns true if version [a] is greater than version [b].
bool semverGt(String a, String b) {
  final va = SemVer.tryParse(a);
  final vb = SemVer.tryParse(b);
  if (va == null || vb == null) return false;
  return va.compareTo(vb) > 0;
}

/// Returns true if version [a] is greater than or equal to version [b].
bool semverGte(String a, String b) {
  final va = SemVer.tryParse(a);
  final vb = SemVer.tryParse(b);
  if (va == null || vb == null) return false;
  return va.compareTo(vb) >= 0;
}

/// Returns true if version [a] is less than version [b].
bool semverLt(String a, String b) {
  final va = SemVer.tryParse(a);
  final vb = SemVer.tryParse(b);
  if (va == null || vb == null) return false;
  return va.compareTo(vb) < 0;
}

/// Returns true if version [a] is less than or equal to version [b].
bool semverLte(String a, String b) {
  final va = SemVer.tryParse(a);
  final vb = SemVer.tryParse(b);
  if (va == null || vb == null) return false;
  return va.compareTo(vb) <= 0;
}

/// Returns the comparison order: -1, 0, or 1.
int semverOrder(String a, String b) {
  final va = SemVer.tryParse(a);
  final vb = SemVer.tryParse(b);
  if (va == null || vb == null) return 0;
  final cmp = va.compareTo(vb);
  if (cmp < 0) return -1;
  if (cmp > 0) return 1;
  return 0;
}

/// Coerce a version string to a clean SemVer (strip build metadata).
String? semverCoerce(String version) {
  final parsed = SemVer.tryParse(version);
  return parsed?.version;
}

// ===========================================================================
// Release Notes (ported from releaseNotes.ts)
// ===========================================================================

/// Maximum number of release notes to show.
const int _maxReleaseNotesShown = 5;

/// URL for the public changelog.
const String changelogUrl =
    'https://github.com/anthropics/neom-claw/blob/main/CHANGELOG.md';

/// URL for raw changelog content.
const String _rawChangelogUrl =
    'https://raw.githubusercontent.com/anthropics/neom-claw/refs/heads/main/CHANGELOG.md';

/// Result of checking for release notes.
class ReleaseNotesResult {
  final bool hasReleaseNotes;
  final List<String> releaseNotes;

  const ReleaseNotesResult({
    required this.hasReleaseNotes,
    required this.releaseNotes,
  });
}

/// Controller for release notes management.
///
/// Handles changelog fetching, caching, parsing, and display of release
/// notes to the user.
class ReleaseNotesController extends SintController {
  /// In-memory cache of changelog content.
  final RxString changelogCache = ''.obs;

  /// Whether changelog has been fetched.
  final RxBool changelogFetched = false.obs;

  /// The config home directory for cache file storage.
  final String configHomeDir;

  /// Current app version.
  final String appVersion;

  /// Whether this is a non-interactive session.
  final bool isNonInteractive;

  /// Whether essential-traffic-only mode is enabled.
  final bool isEssentialTrafficOnly;

  /// HTTP client for fetching changelog (injectable for testing).
  final Future<String?> Function(String url)? _httpGet;

  ReleaseNotesController({
    required this.configHomeDir,
    required this.appVersion,
    this.isNonInteractive = false,
    this.isEssentialTrafficOnly = false,
    Future<String?> Function(String url)? httpGet,
  }) : _httpGet = httpGet;

  /// Get the path for the cached changelog file.
  String get _changelogCachePath => '$configHomeDir/cache/changelog.md';

  /// Reset the changelog cache (for testing).
  void resetChangelogCache() {
    changelogCache.value = '';
    changelogFetched.value = false;
  }

  /// Fetch the changelog from GitHub and store it in cache file.
  /// This runs in the background and does not block the UI.
  Future<void> fetchAndStoreChangelog() async {
    if (isNonInteractive) return;
    if (isEssentialTrafficOnly) return;

    try {
      String? content;
      if (_httpGet != null) {
        content = await _httpGet!(_rawChangelogUrl);
      } else {
        final client = HttpClient();
        try {
          final request = await client.getUrl(Uri.parse(_rawChangelogUrl));
          final response = await request.close();
          if (response.statusCode == 200) {
            content = await response.transform(utf8.decoder).join();
          }
        } finally {
          client.close();
        }
      }

      if (content == null) return;

      // Skip write if content unchanged
      if (content == changelogCache.value) return;

      final cachePath = _changelogCachePath;
      final cacheDir = Directory(cachePath.substring(
        0,
        cachePath.lastIndexOf('/'),
      ));
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      await File(cachePath).writeAsString(content);
      changelogCache.value = content;
    } catch (_) {
      // Silently fail -- this is a background operation
    }
  }

  /// Get the stored changelog from cache file if available.
  Future<String> getStoredChangelog() async {
    if (changelogCache.value.isNotEmpty) return changelogCache.value;

    try {
      final content = await File(_changelogCachePath).readAsString();
      changelogCache.value = content;
      return content;
    } catch (_) {
      changelogCache.value = '';
      return '';
    }
  }

  /// Synchronous accessor for the changelog from memory cache.
  String getStoredChangelogFromMemory() => changelogCache.value;

  /// Parses a changelog string in markdown format into a structured format.
  ///
  /// Returns a map of version numbers to arrays of release notes.
  Map<String, List<String>> parseChangelog(String content) {
    try {
      if (content.isEmpty) return {};

      final releaseNotes = <String, List<String>>{};

      // Split by heading lines (## X.X.X)
      final sections = content.split(RegExp(r'^## ', multiLine: true));
      final relevantSections =
          sections.length > 1 ? sections.sublist(1) : <String>[];

      for (final section in relevantSections) {
        final lines = section.trim().split('\n');
        if (lines.isEmpty) continue;

        final versionLine = lines[0];
        // First part before any dash is the version
        final version = versionLine.split(' - ').first.trim();
        if (version.isEmpty) continue;

        // Extract bullet points
        final notes = lines
            .sublist(1)
            .where((line) => line.trim().startsWith('- '))
            .map((line) => line.trim().substring(2).trim())
            .where((note) => note.isNotEmpty)
            .toList();

        if (notes.isNotEmpty) {
          releaseNotes[version] = notes;
        }
      }

      return releaseNotes;
    } catch (_) {
      return {};
    }
  }

  /// Gets release notes to show based on the previously seen version.
  ///
  /// Shows up to [_maxReleaseNotesShown] items total, prioritizing the most
  /// recent versions.
  List<String> getRecentReleaseNotes({
    required String currentVersion,
    String? previousVersion,
    String? changelogContent,
  }) {
    try {
      final content = changelogContent ?? getStoredChangelogFromMemory();
      final releaseNotes = parseChangelog(content);

      final baseCurrentVersion = semverCoerce(currentVersion);
      final basePreviousVersion =
          previousVersion != null ? semverCoerce(previousVersion) : null;

      if (basePreviousVersion == null ||
          (baseCurrentVersion != null &&
              semverGt(baseCurrentVersion, basePreviousVersion))) {
        final sortedEntries = releaseNotes.entries
            .where((entry) =>
                basePreviousVersion == null ||
                semverGt(entry.key, basePreviousVersion))
            .toList()
          ..sort((a, b) => semverGt(a.key, b.key) ? -1 : 1);
        return sortedEntries
            .map((entry) => entry.value)
            .expand((notes) => notes)
            .where((note) => note.isNotEmpty)
            .take(_maxReleaseNotesShown)
            .toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  /// Gets all release notes as a list of (version, notes) pairs.
  /// Versions are sorted with oldest first.
  List<(String, List<String>)> getAllReleaseNotes({
    String? changelogContent,
  }) {
    try {
      final content = changelogContent ?? getStoredChangelogFromMemory();
      final releaseNotes = parseChangelog(content);

      final sortedVersions = releaseNotes.keys.toList()
        ..sort((a, b) => semverGt(a, b) ? 1 : -1);

      return sortedVersions
          .map((version) {
            final notes = releaseNotes[version];
            if (notes == null || notes.isEmpty) return null;
            final filtered = notes.where((n) => n.isNotEmpty).toList();
            if (filtered.isEmpty) return null;
            return (version, filtered);
          })
          .whereType<(String, List<String>)>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Checks if there are release notes to show based on the last seen version.
  /// Also triggers a fetch of the latest changelog if the version has changed.
  Future<ReleaseNotesResult> checkForReleaseNotes({
    String? lastSeenVersion,
  }) async {
    final cachedChangelog = await getStoredChangelog();

    if (lastSeenVersion != appVersion || cachedChangelog.isEmpty) {
      // Fetch in background, do not await
      fetchAndStoreChangelog();
    }

    final releaseNotes = getRecentReleaseNotes(
      currentVersion: appVersion,
      previousVersion: lastSeenVersion,
      changelogContent: cachedChangelog,
    );

    return ReleaseNotesResult(
      hasReleaseNotes: releaseNotes.isNotEmpty,
      releaseNotes: releaseNotes,
    );
  }

  /// Synchronous variant of checkForReleaseNotes for UI render paths.
  ReleaseNotesResult checkForReleaseNotesSync({
    String? lastSeenVersion,
  }) {
    final releaseNotes = getRecentReleaseNotes(
      currentVersion: appVersion,
      previousVersion: lastSeenVersion,
    );
    return ReleaseNotesResult(
      hasReleaseNotes: releaseNotes.isNotEmpty,
      releaseNotes: releaseNotes,
    );
  }
}

// ===========================================================================
// Auto Updater (ported from autoUpdater.ts)
// ===========================================================================

/// Status of an installation operation.
enum AutoUpdateInstallStatus {
  success,
  noPermissions,
  installFailed,
  inProgress,
}

/// Result of an auto-update operation.
class AutoUpdaterResult {
  final String? version;
  final AutoUpdateInstallStatus status;
  final List<String>? notifications;

  const AutoUpdaterResult({
    this.version,
    required this.status,
    this.notifications,
  });
}

/// Configuration for maximum allowed version (server-side kill switch).
class MaxVersionConfig {
  final String? external;
  final String? ant;
  final String? externalMessage;
  final String? antMessage;

  const MaxVersionConfig({
    this.external,
    this.ant,
    this.externalMessage,
    this.antMessage,
  });
}

/// Release channel for version management.
enum ReleaseChannel {
  latest,
  stable,
}

/// npm dist-tags (latest and stable versions).
class NpmDistTags {
  final String? latest;
  final String? stable;

  const NpmDistTags({
    this.latest,
    this.stable,
  });
}

/// Lock file timeout for preventing concurrent updates.
const Duration _lockTimeout = Duration(minutes: 5);

/// Controller for auto-update functionality.
///
/// Manages version checking, lock file management for preventing concurrent
/// updates, installation, and shell config cleanup.
class AutoUpdaterController extends SintController {
  /// Current app version.
  final String appVersion;

  /// Package URL for npm operations.
  final String packageUrl;

  /// Config home directory.
  final String configHomeDir;

  /// User type (ant, external).
  final String? userType;

  /// Whether running with Bun runtime.
  final bool isRunningWithBun;

  /// Callback for executing shell commands (injectable for testing).
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })? _execCommand;

  /// Current update status.
  final Rx<AutoUpdateInstallStatus?> updateStatus = Rx<AutoUpdateInstallStatus?>(null);

  /// Latest available version.
  final RxnString latestVersion = RxnString();

  AutoUpdaterController({
    required this.appVersion,
    required this.packageUrl,
    required this.configHomeDir,
    this.userType,
    this.isRunningWithBun = false,
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    })? execCommand,
  }) : _execCommand = execCommand;

  /// Get the path to the lock file.
  String get lockFilePath => '$configHomeDir/.update.lock';

  /// Checks if the current version meets the minimum required version.
  ///
  /// Returns the minimum version string if the current version is too old,
  /// or null if the version is acceptable.
  String? assertMinVersion(String minVersion) {
    if (semverLt(appVersion, minVersion)) {
      return minVersion;
    }
    return null;
  }

  /// Returns the maximum allowed version for the current user type.
  String? getMaxVersion(MaxVersionConfig config) {
    if (userType == 'ant') {
      return config.ant?.isNotEmpty == true ? config.ant : null;
    }
    return config.external?.isNotEmpty == true ? config.external : null;
  }

  /// Returns the server-driven message explaining a known issue.
  String? getMaxVersionMessage(MaxVersionConfig config) {
    if (userType == 'ant') {
      return config.antMessage?.isNotEmpty == true ? config.antMessage : null;
    }
    return config.externalMessage?.isNotEmpty == true
        ? config.externalMessage
        : null;
  }

  /// Checks if a target version should be skipped due to minimumVersion
  /// setting.
  bool shouldSkipVersion({
    required String targetVersion,
    String? minimumVersion,
  }) {
    if (minimumVersion == null) return false;
    final shouldSkip = !semverGte(targetVersion, minimumVersion);
    return shouldSkip;
  }

  /// Attempts to acquire a lock for auto-updater.
  /// Returns true if lock was acquired, false if another process holds it.
  Future<bool> acquireLock() async {
    final lockPath = lockFilePath;

    try {
      final lockFile = File(lockPath);
      if (lockFile.existsSync()) {
        final stats = lockFile.statSync();
        final age = DateTime.now().difference(stats.modified);
        if (age < _lockTimeout) {
          return false;
        }
        // Lock is stale -- re-verify and remove
        try {
          final recheck = File(lockPath).statSync();
          final recheckAge = DateTime.now().difference(recheck.modified);
          if (recheckAge < _lockTimeout) {
            return false;
          }
          lockFile.deleteSync();
        } on FileSystemException {
          return false;
        }
      }
    } on FileSystemException catch (e) {
      // File doesn't exist -- proceed to create
      if (e.osError?.errorCode != 2) {
        // Not ENOENT
        return false;
      }
    }

    // Create lock file
    try {
      final lockFile = File(lockPath);
      lockFile.writeAsStringSync(
        '${pid}',
        mode: FileMode.writeOnly,
      );
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Releases the update lock if it is held by this process.
  Future<void> releaseLock() async {
    final lockPath = lockFilePath;
    try {
      final lockFile = File(lockPath);
      if (!lockFile.existsSync()) return;
      final lockData = lockFile.readAsStringSync();
      if (lockData == '$pid') {
        lockFile.deleteSync();
      }
    } on FileSystemException {
      // Ignore errors during lock release
    }
  }

  /// Get the latest version from npm registry for a given channel.
  Future<String?> getLatestVersion(ReleaseChannel channel) async {
    final npmTag = channel == ReleaseChannel.stable ? 'stable' : 'latest';

    try {
      final result = await _runCommand(
        'npm',
        ['view', '$packageUrl@$npmTag', 'version', '--prefer-online'],
      );
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } catch (_) {
      return null;
    }
  }

  /// Get npm dist-tags (latest and stable versions).
  Future<NpmDistTags> getNpmDistTags() async {
    try {
      final result = await _runCommand(
        'npm',
        ['view', packageUrl, 'dist-tags', '--json', '--prefer-online'],
      );

      if (result.exitCode != 0) {
        return const NpmDistTags();
      }

      final parsed = jsonDecode((result.stdout as String).trim())
          as Map<String, dynamic>;
      return NpmDistTags(
        latest: parsed['latest'] as String?,
        stable: parsed['stable'] as String?,
      );
    } catch (_) {
      return const NpmDistTags();
    }
  }

  /// Get version history from npm registry.
  /// Returns versions sorted newest-first, limited to [limit].
  Future<List<String>> getVersionHistory(int limit) async {
    if (userType != 'ant') return [];

    try {
      final result = await _runCommand(
        'npm',
        ['view', packageUrl, 'versions', '--json', '--prefer-online'],
      );

      if (result.exitCode != 0) return [];

      final versions =
          (jsonDecode((result.stdout as String).trim()) as List<dynamic>)
              .cast<String>();
      // Take last N versions, then reverse to get newest first
      final start = max(0, versions.length - limit);
      return versions.sublist(start).reversed.toList();
    } catch (_) {
      return [];
    }
  }

  /// Check global install permissions.
  Future<({bool hasPermissions, String? npmPrefix})>
      checkGlobalInstallPermissions() async {
    try {
      final prefix = await _getInstallationPrefix();
      if (prefix == null) {
        return (hasPermissions: false, npmPrefix: null);
      }

      try {
        // Check write access
        final dir = Directory(prefix);
        if (dir.existsSync()) {
          return (hasPermissions: true, npmPrefix: prefix);
        }
        return (hasPermissions: false, npmPrefix: prefix);
      } catch (_) {
        return (hasPermissions: false, npmPrefix: prefix);
      }
    } catch (_) {
      return (hasPermissions: false, npmPrefix: null);
    }
  }

  /// Get the installation prefix.
  Future<String?> _getInstallationPrefix() async {
    try {
      ProcessResult result;
      if (isRunningWithBun) {
        result = await _runCommand('bun', ['pm', 'bin', '-g']);
      } else {
        result = await _runCommand('npm', ['-g', 'config', 'get', 'prefix']);
      }
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } catch (_) {
      return null;
    }
  }

  /// Install a global package.
  Future<AutoUpdateInstallStatus> installGlobalPackage({
    String? specificVersion,
  }) async {
    if (!await acquireLock()) {
      return AutoUpdateInstallStatus.inProgress;
    }

    try {
      final permissions = await checkGlobalInstallPermissions();
      if (!permissions.hasPermissions) {
        return AutoUpdateInstallStatus.noPermissions;
      }

      final packageSpec = specificVersion != null
          ? '$packageUrl@$specificVersion'
          : packageUrl;

      final packageManager = isRunningWithBun ? 'bun' : 'npm';
      final result = await _runCommand(
        packageManager,
        ['install', '-g', packageSpec],
      );

      if (result.exitCode != 0) {
        return AutoUpdateInstallStatus.installFailed;
      }

      updateStatus.value = AutoUpdateInstallStatus.success;
      return AutoUpdateInstallStatus.success;
    } finally {
      await releaseLock();
    }
  }

  /// Run a shell command.
  Future<ProcessResult> _runCommand(
    String executable,
    List<String> arguments,
  ) async {
    if (_execCommand != null) {
      return _execCommand!(
        executable,
        arguments,
        workingDirectory: Platform.environment['HOME'],
      );
    }
    return Process.run(
      executable,
      arguments,
      workingDirectory: Platform.environment['HOME'],
    );
  }
}

// ===========================================================================
// User (ported from user.ts)
// ===========================================================================

/// GitHub Actions metadata when running in CI.
class GitHubActionsMetadata {
  final String? actor;
  final String? actorId;
  final String? repository;
  final String? repositoryId;
  final String? repositoryOwner;
  final String? repositoryOwnerId;

  const GitHubActionsMetadata({
    this.actor,
    this.actorId,
    this.repository,
    this.repositoryId,
    this.repositoryOwner,
    this.repositoryOwnerId,
  });
}

/// Core user data used as base for all analytics providers.
class CoreUserData {
  final String deviceId;
  final String sessionId;
  final String? email;
  final String appVersion;
  final String platform;
  final String? organizationUuid;
  final String? accountUuid;
  final String? userType;
  final String? subscriptionType;
  final String? rateLimitTier;
  final int? firstTokenTime;
  final GitHubActionsMetadata? githubActionsMetadata;

  const CoreUserData({
    required this.deviceId,
    required this.sessionId,
    this.email,
    required this.appVersion,
    required this.platform,
    this.organizationUuid,
    this.accountUuid,
    this.userType,
    this.subscriptionType,
    this.rateLimitTier,
    this.firstTokenTime,
    this.githubActionsMetadata,
  });
}

/// OAuth account information.
class OAuthAccountInfo {
  final String? emailAddress;
  final String? organizationUuid;
  final String? accountUuid;

  const OAuthAccountInfo({
    this.emailAddress,
    this.organizationUuid,
    this.accountUuid,
  });
}

/// Controller for user data and email resolution.
///
/// Manages user identity, email fetching, and core user data assembly
/// for analytics and feature flagging.
class UserController extends SintController {
  /// Cached email (null means not fetched yet).
  String? _cachedEmail;
  bool _emailFetched = false;
  Future<String?>? _emailFetchPromise;

  /// Current session ID.
  final String sessionId;

  /// Device ID.
  final String deviceId;

  /// App version.
  final String appVersion;

  /// Platform identifier.
  final String platform;

  /// User type (ant, external).
  final String? userType;

  /// Current working directory (for git operations).
  final String cwd;

  /// OAuth account info provider (injectable).
  final OAuthAccountInfo? Function()? _getOAuthAccountInfo;

  /// Subscription type provider (injectable).
  final String? Function()? _getSubscriptionType;

  /// Rate limit tier provider (injectable).
  final String? Function()? _getRateLimitTier;

  /// Git email fetcher (injectable for testing).
  final Future<String?> Function()? _fetchGitEmail;

  /// Cached core user data.
  CoreUserData? _cachedCoreUserData;

  UserController({
    required this.sessionId,
    required this.deviceId,
    required this.appVersion,
    required this.platform,
    required this.cwd,
    this.userType,
    OAuthAccountInfo? Function()? getOAuthAccountInfo,
    String? Function()? getSubscriptionType,
    String? Function()? getRateLimitTier,
    Future<String?> Function()? fetchGitEmail,
  })  : _getOAuthAccountInfo = getOAuthAccountInfo,
        _getSubscriptionType = getSubscriptionType,
        _getRateLimitTier = getRateLimitTier,
        _fetchGitEmail = fetchGitEmail;

  /// Initialize user data asynchronously. Should be called early in startup.
  Future<void> initUser() async {
    if (_emailFetched || _emailFetchPromise != null) return;

    _emailFetchPromise = _getEmailAsync();
    _cachedEmail = await _emailFetchPromise;
    _emailFetched = true;
    _emailFetchPromise = null;
    _cachedCoreUserData = null; // Clear memoization
  }

  /// Reset all user data caches.
  void resetUserCache() {
    _cachedEmail = null;
    _emailFetched = false;
    _emailFetchPromise = null;
    _cachedCoreUserData = null;
  }

  /// Get core user data.
  CoreUserData getCoreUserData({
    bool includeAnalyticsMetadata = false,
  }) {
    if (_cachedCoreUserData != null && !includeAnalyticsMetadata) {
      return _cachedCoreUserData!;
    }

    String? subscriptionType;
    String? rateLimitTier;
    int? firstTokenTime;

    if (includeAnalyticsMetadata) {
      subscriptionType = _getSubscriptionType?.call();
      rateLimitTier = _getRateLimitTier?.call();
    }

    final oauthAccount = _getOAuthAccountInfo?.call();

    final data = CoreUserData(
      deviceId: deviceId,
      sessionId: sessionId,
      email: _getEmail(),
      appVersion: appVersion,
      platform: platform,
      organizationUuid: oauthAccount?.organizationUuid,
      accountUuid: oauthAccount?.accountUuid,
      userType: userType,
      subscriptionType: subscriptionType,
      rateLimitTier: rateLimitTier,
      firstTokenTime: firstTokenTime,
    );

    if (!includeAnalyticsMetadata) {
      _cachedCoreUserData = data;
    }

    return data;
  }

  /// Get user data for feature flagging (same as core with analytics).
  CoreUserData getUserForGrowthBook() {
    return getCoreUserData(includeAnalyticsMetadata: true);
  }

  /// Get the user's email synchronously.
  String? _getEmail() {
    if (_emailFetched && _cachedEmail != null) return _cachedEmail;

    final oauthAccount = _getOAuthAccountInfo?.call();
    if (oauthAccount?.emailAddress != null) return oauthAccount!.emailAddress;

    if (userType != 'ant') return null;

    final cooCreator = Platform.environment['COO_CREATOR'];
    if (cooCreator != null) return '$cooCreator@anthropic.com';

    return null;
  }

  /// Get the user's email asynchronously.
  Future<String?> _getEmailAsync() async {
    final oauthAccount = _getOAuthAccountInfo?.call();
    if (oauthAccount?.emailAddress != null) return oauthAccount!.emailAddress;

    if (userType != 'ant') return null;

    final cooCreator = Platform.environment['COO_CREATOR'];
    if (cooCreator != null) return '$cooCreator@anthropic.com';

    // Try git email
    if (_fetchGitEmail != null) {
      return _fetchGitEmail!();
    }

    try {
      final result = await Process.run(
        'git',
        ['config', '--get', 'user.email'],
        workingDirectory: cwd,
      );
      if (result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}

    return null;
  }
}
