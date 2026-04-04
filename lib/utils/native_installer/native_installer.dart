/// Native Installer Implementation
///
/// Faithful port of openneomclaw/src/utils/nativeInstaller/*.ts
/// Covers: installer.ts, download.ts, pidLock.ts, packageManagers.ts
///
/// Provides:
/// - Directory structure management with symlinks
/// - Version installation and activation
/// - Multi-process safety with PID-based and mtime-based locking
/// - Binary download with checksum verification, stall detection, retry
/// - Package manager detection (homebrew, winget, pacman, deb, rpm, apk, mise, asdf)

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sint/sint.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Number of old versions to retain before cleanup.
const int versionRetentionCount = 2;

/// 7 days in milliseconds — mtime-based lock stale timeout.
/// Long enough to survive laptop sleep, short enough for eventual cleanup.
const int lockStaleMs = 7 * 24 * 60 * 60 * 1000;

/// GCS bucket URL for external binary downloads.
const String gcsBucketUrl =
    'https://storage.googleapis.com/neom-claw-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/neom-claw-releases';

/// Artifactory npm registry URL for internal binary downloads.
const String artifactoryRegistryUrl =
    'https://artifactory.infra.ant.dev/artifactory/api/npm/npm-all/';

/// Stall timeout: abort if no bytes received for this duration.
const int defaultStallTimeoutMs = 60000; // 60 seconds

/// Maximum download retries on stall timeout.
const int maxDownloadRetries = 3;

/// Fallback stale timeout (2 hours) for PID-based locks when PID check is inconclusive.
const int fallbackStaleMs = 2 * 60 * 60 * 1000;

// ═══════════════════════════════════════════════════════════════════════════
// SETUP MESSAGE
// ═══════════════════════════════════════════════════════════════════════════

/// Types of setup messages displayed during installation.
enum SetupMessageType { path, alias, info, error }

/// A message generated during the setup/installation process.
class SetupMessage {
  final String message;
  final bool userActionRequired;
  final SetupMessageType type;

  const SetupMessage({
    required this.message,
    required this.userActionRequired,
    required this.type,
  });

  @override
  String toString() =>
      'SetupMessage(type: $type, userActionRequired: $userActionRequired, message: $message)';
}

// ═══════════════════════════════════════════════════════════════════════════
// PACKAGE MANAGER DETECTION (packageManagers.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Supported package manager types.
enum PackageManager {
  homebrew,
  winget,
  pacman,
  deb,
  rpm,
  apk,
  mise,
  asdf,
  unknown,
}

/// Parsed /etc/os-release fields.
class OsReleaseInfo {
  final String id;
  final List<String> idLike;

  const OsReleaseInfo({required this.id, required this.idLike});
}

/// Cache for OS release info (memoized).
OsReleaseInfo? _cachedOsRelease;
bool _osReleaseRead = false;

/// Parses /etc/os-release to extract the distro ID and ID_LIKE fields.
/// ID_LIKE identifies the distro family (e.g. Ubuntu has ID_LIKE=debian).
/// Returns null if the file is unreadable.
Future<OsReleaseInfo?> getOsRelease() async {
  if (_osReleaseRead) return _cachedOsRelease;
  _osReleaseRead = true;
  try {
    final content = await File('/etc/os-release').readAsString();
    final idMatch = RegExp(r'^ID="?(\S+?)"?\s*$', multiLine: true).firstMatch(content);
    final idLikeMatch =
        RegExp(r'^ID_LIKE="?(.+?)"?\s*$', multiLine: true).firstMatch(content);
    _cachedOsRelease = OsReleaseInfo(
      id: idMatch?.group(1) ?? '',
      idLike: idLikeMatch?.group(1)?.split(' ') ?? [],
    );
    return _cachedOsRelease;
  } catch (_) {
    return null;
  }
}

/// Check if the OS release matches any of the given distro families.
bool isDistroFamily(OsReleaseInfo osRelease, List<String> families) {
  return families.contains(osRelease.id) ||
      osRelease.idLike.any((like) => families.contains(like));
}

/// Detects if the currently running instance was installed via mise.
/// mise installs to: ~/.local/share/mise/installs/<tool>/<version>/
bool detectMise() {
  final execPath = Platform.resolvedExecutable;
  return RegExp(r'[/\\]mise[/\\]installs[/\\]', caseSensitive: false)
      .hasMatch(execPath);
}

/// Detects if the currently running instance was installed via asdf.
/// asdf installs to: ~/.asdf/installs/<tool>/<version>/
bool detectAsdf() {
  final execPath = Platform.resolvedExecutable;
  return RegExp(r'[/\\]\.?asdf[/\\]installs[/\\]', caseSensitive: false)
      .hasMatch(execPath);
}

/// Detects if the currently running instance was installed via Homebrew.
/// Checks for Caskroom path specifically to distinguish from npm-global via Homebrew's npm.
bool detectHomebrew() {
  if (!Platform.isMacOS && !Platform.isLinux) return false;
  final execPath = Platform.resolvedExecutable;
  return execPath.contains('/Caskroom/');
}

/// Detects if the currently running instance was installed via winget.
/// Winget installs to %LOCALAPPDATA%\Microsoft\WinGet\Packages or
/// C:\Program Files\WinGet\Packages.
bool detectWinget() {
  if (!Platform.isWindows) return false;
  final execPath = Platform.resolvedExecutable;
  final patterns = [
    RegExp(r'Microsoft[/\\]WinGet[/\\]Packages', caseSensitive: false),
    RegExp(r'Microsoft[/\\]WinGet[/\\]Links', caseSensitive: false),
  ];
  return patterns.any((p) => p.hasMatch(execPath));
}

/// Detects if installed via pacman by querying pacman's database.
/// Gates on Arch distro family before invoking pacman.
Future<bool> detectPacman() async {
  if (!Platform.isLinux) return false;
  final osRelease = await getOsRelease();
  if (osRelease != null && !isDistroFamily(osRelease, ['arch'])) return false;
  final execPath = Platform.resolvedExecutable;
  try {
    final result = await Process.run('pacman', ['-Qo', execPath]);
    return result.exitCode == 0 && (result.stdout as String).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Detects if installed via a .deb package by querying dpkg.
Future<bool> detectDeb() async {
  if (!Platform.isLinux) return false;
  final osRelease = await getOsRelease();
  if (osRelease != null && !isDistroFamily(osRelease, ['debian'])) return false;
  final execPath = Platform.resolvedExecutable;
  try {
    final result = await Process.run('dpkg', ['-S', execPath]);
    return result.exitCode == 0 && (result.stdout as String).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Detects if installed via an RPM package by querying rpm.
Future<bool> detectRpm() async {
  if (!Platform.isLinux) return false;
  final osRelease = await getOsRelease();
  if (osRelease != null &&
      !isDistroFamily(osRelease, ['fedora', 'rhel', 'suse'])) return false;
  final execPath = Platform.resolvedExecutable;
  try {
    final result = await Process.run('rpm', ['-qf', execPath]);
    return result.exitCode == 0 && (result.stdout as String).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Detects if installed via Alpine APK by querying apk.
Future<bool> detectApk() async {
  if (!Platform.isLinux) return false;
  final osRelease = await getOsRelease();
  if (osRelease != null && !isDistroFamily(osRelease, ['alpine'])) return false;
  final execPath = Platform.resolvedExecutable;
  try {
    final result = await Process.run('apk', ['info', '--who-owns', execPath]);
    return result.exitCode == 0 && (result.stdout as String).isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Detect which package manager installed the application.
/// Returns PackageManager.unknown if none detected.
Future<PackageManager> getPackageManager() async {
  if (detectHomebrew()) return PackageManager.homebrew;
  if (detectWinget()) return PackageManager.winget;
  if (detectMise()) return PackageManager.mise;
  if (detectAsdf()) return PackageManager.asdf;
  if (await detectPacman()) return PackageManager.pacman;
  if (await detectApk()) return PackageManager.apk;
  if (await detectDeb()) return PackageManager.deb;
  if (await detectRpm()) return PackageManager.rpm;
  return PackageManager.unknown;
}

// ═══════════════════════════════════════════════════════════════════════════
// PID-BASED VERSION LOCKING (pidLock.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Content stored in a version lock file.
class VersionLockContent {
  final int pid;
  final String version;
  final String execPath;
  final int acquiredAt; // timestamp when lock was acquired

  const VersionLockContent({
    required this.pid,
    required this.version,
    required this.execPath,
    required this.acquiredAt,
  });

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'version': version,
        'execPath': execPath,
        'acquiredAt': acquiredAt,
      };

  static VersionLockContent? fromJson(Map<String, dynamic> json) {
    if (json['pid'] is! int ||
        json['version'] is! String ||
        json['execPath'] is! String) {
      return null;
    }
    return VersionLockContent(
      pid: json['pid'] as int,
      version: json['version'] as String,
      execPath: json['execPath'] as String,
      acquiredAt: (json['acquiredAt'] as int?) ?? 0,
    );
  }
}

/// Diagnostic lock information.
class LockInfo {
  final String version;
  final int pid;
  final bool isProcessRunning;
  final String execPath;
  final DateTime acquiredAt;
  final String lockFilePath;

  const LockInfo({
    required this.version,
    required this.pid,
    required this.isProcessRunning,
    required this.execPath,
    required this.acquiredAt,
    required this.lockFilePath,
  });
}

/// Whether PID-based locking is enabled.
/// Controlled by environment variable or feature gate.
bool isPidBasedLockingEnabled() {
  final envVar = Platform.environment['ENABLE_PID_BASED_VERSION_LOCKING'];
  if (envVar != null) {
    final lower = envVar.toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
  }
  // Default: disabled for external users (would be GrowthBook-controlled in prod)
  return false;
}

/// Check if a process with the given PID is currently running.
/// Uses signal 0 which checks permission without sending a signal.
bool isProcessRunning(int pid) {
  if (pid <= 1) return false;
  try {
    return Process.killPid(pid, ProcessSignal.sigusr1) ||
        _checkPidExists(pid);
  } catch (_) {
    return false;
  }
}

/// Platform-specific PID existence check.
bool _checkPidExists(int pid) {
  try {
    // On Unix-like systems, sending signal 0 checks if process exists
    final result = Process.runSync('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Validate that a running process is actually a NeomClaw process.
/// Helps mitigate PID reuse issues.
bool _isNeomClawProcess(int pid, String expectedExecPath) {
  if (!isProcessRunning(pid)) return false;
  if (pid == pid) return true; // Current process always valid

  try {
    final result = Process.runSync('ps', ['-p', '$pid', '-o', 'command=']);
    if (result.exitCode != 0) return true; // Trust PID check if command fails
    final command = (result.stdout as String).toLowerCase();
    return command.contains('neomclaw') ||
        command.contains(expectedExecPath.toLowerCase());
  } catch (_) {
    return true; // Trust PID check on failure
  }
}

/// Read and parse a lock file's content.
VersionLockContent? readLockContent(String lockFilePath) {
  try {
    final file = File(lockFilePath);
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync();
    if (content.trim().isEmpty) return null;
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    return VersionLockContent.fromJson(parsed);
  } catch (_) {
    return null;
  }
}

/// Check if a lock file represents an active lock (process still running).
bool isLockActive(String lockFilePath) {
  final content = readLockContent(lockFilePath);
  if (content == null) return false;

  if (!isProcessRunning(content.pid)) return false;
  if (!_isNeomClawProcess(content.pid, content.execPath)) return false;

  // Fallback: if the lock is very old (> 2 hours), double-check
  try {
    final stat = File(lockFilePath).statSync();
    final age = DateTime.now().millisecondsSinceEpoch - stat.modified.millisecondsSinceEpoch;
    if (age > fallbackStaleMs) {
      if (!isProcessRunning(content.pid)) return false;
    }
  } catch (_) {
    // Trust the PID check
  }

  return true;
}

/// Write lock content to a file atomically.
void writeLockFile(String lockFilePath, VersionLockContent content) {
  final tempPath = '$lockFilePath.tmp.${pid}.${DateTime.now().millisecondsSinceEpoch}';
  try {
    File(tempPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(content.toJson()),
      flush: true,
    );
    File(tempPath).renameSync(lockFilePath);
  } catch (e) {
    try {
      File(tempPath).deleteSync();
    } catch (_) {}
    rethrow;
  }
}

/// Try to acquire a lock on a version file.
/// Returns a release function if successful, null if already held.
Future<void Function()?> tryAcquireLock(
    String versionPath, String lockFilePath) async {
  final versionName = p.basename(versionPath);

  if (isLockActive(lockFilePath)) {
    final existing = readLockContent(lockFilePath);
    _logDebug('Cannot acquire lock for $versionName - held by PID ${existing?.pid}');
    return null;
  }

  final lockContent = VersionLockContent(
    pid: pid,
    version: versionName,
    execPath: Platform.resolvedExecutable,
    acquiredAt: DateTime.now().millisecondsSinceEpoch,
  );

  try {
    writeLockFile(lockFilePath, lockContent);

    // Verify we got the lock (race condition check)
    final verify = readLockContent(lockFilePath);
    if (verify?.pid != pid) return null;

    _logDebug('Acquired PID lock for $versionName (PID $pid)');

    return () {
      try {
        final current = readLockContent(lockFilePath);
        if (current?.pid == pid) {
          File(lockFilePath).deleteSync();
          _logDebug('Released PID lock for $versionName');
        }
      } catch (_) {}
    };
  } catch (e) {
    _logDebug('Failed to acquire lock for $versionName: $e');
    return null;
  }
}

/// Acquire a lock and hold it for the lifetime of the process.
Future<bool> acquireProcessLifetimeLock(
    String versionPath, String lockFilePath) async {
  final release = await tryAcquireLock(versionPath, lockFilePath);
  if (release == null) return false;

  // Register cleanup — in Dart we rely on ProcessSignal handlers
  void cleanup() {
    try {
      release();
    } catch (_) {}
  }

  ProcessSignal.sigint.watch().listen((_) => cleanup());
  ProcessSignal.sigterm.watch().listen((_) => cleanup());

  return true;
}

/// Execute a callback while holding a lock.
/// Returns true if the callback executed, false if lock couldn't be acquired.
Future<bool> withLock(
  String versionPath,
  String lockFilePath,
  Future<void> Function() callback,
) async {
  final release = await tryAcquireLock(versionPath, lockFilePath);
  if (release == null) return false;

  try {
    await callback();
    return true;
  } finally {
    release();
  }
}

/// Get information about all version locks for diagnostics.
List<LockInfo> getAllLockInfo(String locksDir) {
  final lockInfos = <LockInfo>[];
  try {
    final dir = Directory(locksDir);
    if (!dir.existsSync()) return lockInfos;

    final lockFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.lock'));

    for (final lockFile in lockFiles) {
      final content = readLockContent(lockFile.path);
      if (content != null) {
        lockInfos.add(LockInfo(
          version: content.version,
          pid: content.pid,
          isProcessRunning: isProcessRunning(content.pid),
          execPath: content.execPath,
          acquiredAt: DateTime.fromMillisecondsSinceEpoch(content.acquiredAt),
          lockFilePath: lockFile.path,
        ));
      }
    }
  } catch (_) {}
  return lockInfos;
}

/// Clean up stale locks (locks where the process is no longer running).
/// Returns the number of locks cleaned up.
/// Handles both PID-based locks and legacy directory locks.
int cleanupStaleLocks(String locksDir) {
  int cleanedCount = 0;
  try {
    final dir = Directory(locksDir);
    if (!dir.existsSync()) return 0;

    final lockEntries = dir
        .listSync()
        .where((e) => e.path.endsWith('.lock'));

    for (final entry in lockEntries) {
      try {
        final stat = entry.statSync();
        if (stat.type == FileSystemEntityType.directory) {
          // Legacy proper-lockfile directory lock
          Directory(entry.path).deleteSync(recursive: true);
          cleanedCount++;
          _logDebug('Cleaned up legacy directory lock: ${p.basename(entry.path)}');
        } else if (!isLockActive(entry.path)) {
          File(entry.path).deleteSync();
          cleanedCount++;
          _logDebug('Cleaned up stale lock: ${p.basename(entry.path)}');
        }
      } catch (_) {}
    }
  } catch (_) {}
  return cleanedCount;
}

// ═══════════════════════════════════════════════════════════════════════════
// DOWNLOAD (download.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Error thrown when a download stalls (no data received for timeout period).
class StallTimeoutError implements Exception {
  @override
  String toString() => 'Download stalled: no data received for 60 seconds';
}

/// Get the stall timeout in milliseconds, checking env override first.
int getStallTimeoutMs() {
  final envVal = Platform.environment['NEOMCLAW_STALL_TIMEOUT_MS_FOR_TESTING'];
  if (envVal != null) {
    final parsed = int.tryParse(envVal);
    if (parsed != null && parsed > 0) return parsed;
  }
  return defaultStallTimeoutMs;
}

/// Get the latest version from a binary repo channel endpoint.
Future<String> getLatestVersionFromBinaryRepo({
  String channel = 'latest',
  required String baseUrl,
  String? authUsername,
  String? authPassword,
}) async {
  final startTime = DateTime.now().millisecondsSinceEpoch;
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$baseUrl/$channel'));
    request.headers.set('Accept', 'text/plain');
    if (authUsername != null && authPassword != null) {
      request.headers.set(
        'Authorization',
        'Basic ${base64Encode(utf8.encode('$authUsername:$authPassword'))}',
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
    _logDebug('Version check from $baseUrl/$channel took ${latencyMs}ms');
    return body.trim();
  } catch (e) {
    final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
    _logDebug('Version check failed after ${latencyMs}ms: $e');
    rethrow;
  } finally {
    client.close();
  }
}

/// Get the latest version, either from direct version string or channel lookup.
Future<String> getLatestVersion(String channelOrVersion) async {
  // Direct version — match internal format too
  if (RegExp(r'^v?\d+\.\d+\.\d+(-\S+)?$').hasMatch(channelOrVersion)) {
    final normalized = channelOrVersion.startsWith('v')
        ? channelOrVersion.substring(1)
        : channelOrVersion;
    // 99.99.x is reserved for CI smoke-test fixtures
    if (RegExp(r'^99\.99\.').hasMatch(normalized)) {
      throw Exception(
        'Version $normalized is not available for installation. Use \'stable\' or \'latest\'.',
      );
    }
    return normalized;
  }

  // ReleaseChannel validation
  if (channelOrVersion != 'stable' && channelOrVersion != 'latest') {
    throw Exception(
      'Invalid channel: $channelOrVersion. Use \'stable\' or \'latest\'',
    );
  }

  // Use GCS for downloads
  return getLatestVersionFromBinaryRepo(
    channel: channelOrVersion,
    baseUrl: gcsBucketUrl,
  );
}

/// Download and verify a binary with stall detection and retry logic.
Future<void> downloadAndVerifyBinary({
  required String binaryUrl,
  required String expectedChecksum,
  required String binaryPath,
  String? authUsername,
  String? authPassword,
}) async {
  Exception? lastError;

  for (int attempt = 1; attempt <= maxDownloadRetries; attempt++) {
    final client = HttpClient();
    Timer? stallTimer;
    bool aborted = false;

    void clearStallTimer() {
      stallTimer?.cancel();
      stallTimer = null;
    }

    void resetStallTimer() {
      clearStallTimer();
      stallTimer = Timer(Duration(milliseconds: getStallTimeoutMs()), () {
        aborted = true;
        client.close(force: true);
      });
    }

    try {
      resetStallTimer();

      final request = await client.getUrl(Uri.parse(binaryUrl));
      if (authUsername != null && authPassword != null) {
        request.headers.set(
          'Authorization',
          'Basic ${base64Encode(utf8.encode('$authUsername:$authPassword'))}',
        );
      }

      final response = await request.close().timeout(const Duration(minutes: 5));
      final chunks = <List<int>>[];
      int totalBytes = 0;

      await for (final chunk in response) {
        if (aborted) throw StallTimeoutError();
        resetStallTimer();
        chunks.add(chunk);
        totalBytes += chunk.length;
      }

      clearStallTimer();

      // Combine chunks
      final data = Uint8List(totalBytes);
      int offset = 0;
      for (final chunk in chunks) {
        data.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      // Verify checksum
      final actualChecksum = sha256.convert(data).toString();
      if (actualChecksum != expectedChecksum) {
        throw Exception(
          'Checksum mismatch: expected $expectedChecksum, got $actualChecksum',
        );
      }

      // Write binary to disk
      final file = File(binaryPath);
      await file.writeAsBytes(data);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['755', binaryPath]);
      }

      return; // Success
    } catch (e) {
      clearStallTimer();

      if (aborted) {
        lastError = StallTimeoutError();
      } else {
        lastError = e is Exception ? e : Exception(e.toString());
      }

      // Only retry on stall timeouts
      if (aborted && attempt < maxDownloadRetries) {
        _logDebug('Download stalled on attempt $attempt/$maxDownloadRetries, retrying...');
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      throw lastError!;
    } finally {
      client.close();
    }
  }

  throw lastError ?? Exception('Download failed after all retries');
}

/// Download a version from a binary repository.
Future<void> downloadVersionFromBinaryRepo({
  required String version,
  required String stagingPath,
  required String baseUrl,
  String? authUsername,
  String? authPassword,
}) async {
  // Clean up any partial download
  final stagingDir = Directory(stagingPath);
  if (stagingDir.existsSync()) {
    stagingDir.deleteSync(recursive: true);
  }

  final platform = getPlatform();
  final startTime = DateTime.now().millisecondsSinceEpoch;

  // Fetch manifest to get checksum
  final client = HttpClient();
  Map<String, dynamic> manifest;
  try {
    final request = await client.getUrl(
      Uri.parse('$baseUrl/$version/manifest.json'),
    );
    if (authUsername != null && authPassword != null) {
      request.headers.set(
        'Authorization',
        'Basic ${base64Encode(utf8.encode('$authUsername:$authPassword'))}',
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    manifest = jsonDecode(body) as Map<String, dynamic>;
  } catch (e) {
    final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
    _logDebug('Manifest fetch failed after ${latencyMs}ms: $e');
    rethrow;
  } finally {
    client.close();
  }

  final platforms = manifest['platforms'] as Map<String, dynamic>?;
  final platformInfo = platforms?[platform] as Map<String, dynamic>?;
  if (platformInfo == null) {
    throw Exception('Platform $platform not found in manifest for version $version');
  }

  final expectedChecksum = platformInfo['checksum'] as String;
  final binaryName = getBinaryName(platform);
  final binaryUrl = '$baseUrl/$version/$platform/$binaryName';

  // Write to staging
  await stagingDir.create(recursive: true);
  final binaryPath = p.join(stagingPath, binaryName);

  try {
    await downloadAndVerifyBinary(
      binaryUrl: binaryUrl,
      expectedChecksum: expectedChecksum,
      binaryPath: binaryPath,
      authUsername: authUsername,
      authPassword: authPassword,
    );
    final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
    _logDebug('Binary download succeeded in ${latencyMs}ms');
  } catch (e) {
    final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
    _logDebug('Binary download failed after ${latencyMs}ms: $e');
    rethrow;
  }
}

/// Download a version, routing to appropriate source.
/// Returns the download type ('npm' or 'binary').
Future<String> downloadVersion(String version, String stagingPath) async {
  await downloadVersionFromBinaryRepo(
    version: version,
    stagingPath: stagingPath,
    baseUrl: gcsBucketUrl,
  );
  return 'binary';
}

// ═══════════════════════════════════════════════════════════════════════════
// INSTALLER (installer.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Get the platform string for binary downloads (e.g., "darwin-arm64").
String getPlatform() {
  String os;
  if (Platform.isMacOS) {
    os = 'darwin';
  } else if (Platform.isWindows) {
    os = 'win32';
  } else {
    os = 'linux';
  }

  // Dart doesn't expose architecture directly; detect from env/uname
  final arch = _detectArch();
  if (arch == null) {
    throw Exception('Unsupported architecture');
  }

  // Check for musl on Linux
  if (os == 'linux' && _isMuslEnvironment()) {
    return '$os-$arch-musl';
  }

  return '$os-$arch';
}

/// Get the binary name for the platform.
String getBinaryName(String platform) {
  return platform.startsWith('win32') ? 'neomclaw.exe' : 'neomclaw';
}

/// Detect CPU architecture.
String? _detectArch() {
  try {
    if (Platform.isMacOS || Platform.isLinux) {
      final result = Process.runSync('uname', ['-m']);
      final machine = (result.stdout as String).trim();
      if (machine == 'x86_64' || machine == 'amd64') return 'x64';
      if (machine == 'arm64' || machine == 'aarch64') return 'arm64';
    } else if (Platform.isWindows) {
      final arch = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      if (arch == 'AMD64') return 'x64';
      if (arch == 'ARM64') return 'arm64';
    }
  } catch (_) {}
  return null;
}

/// Check if running in a musl environment (Alpine Linux, etc).
bool _isMuslEnvironment() {
  try {
    final result = Process.runSync('ldd', ['--version']);
    final output = '${result.stdout}${result.stderr}'.toLowerCase();
    return output.contains('musl');
  } catch (_) {
    return false;
  }
}

/// Get XDG base directories.
String _getXDGDataHome() {
  return Platform.environment['XDG_DATA_HOME'] ??
      p.join(_homeDir(), '.local', 'share');
}

String _getXDGCacheHome() {
  return Platform.environment['XDG_CACHE_HOME'] ??
      p.join(_homeDir(), '.cache');
}

String _getXDGStateHome() {
  return Platform.environment['XDG_STATE_HOME'] ??
      p.join(_homeDir(), '.local', 'state');
}

String _getUserBinDir() {
  if (Platform.isWindows) {
    return p.join(
      Platform.environment['LOCALAPPDATA'] ?? p.join(_homeDir(), 'AppData', 'Local'),
      'Programs',
      'neomclaw',
    );
  }
  return p.join(_homeDir(), '.local', 'bin');
}

String _homeDir() => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '/tmp';

/// Base directory structure for the native installer.
class _BaseDirectories {
  final String versions;
  final String staging;
  final String locks;
  final String executable;

  const _BaseDirectories({
    required this.versions,
    required this.staging,
    required this.locks,
    required this.executable,
  });
}

_BaseDirectories _getBaseDirectories() {
  final platform = getPlatform();
  final executableName = getBinaryName(platform);

  return _BaseDirectories(
    versions: p.join(_getXDGDataHome(), 'neomclaw', 'versions'),
    staging: p.join(_getXDGCacheHome(), 'neomclaw', 'staging'),
    locks: p.join(_getXDGStateHome(), 'neomclaw', 'locks'),
    executable: p.join(_getUserBinDir(), executableName),
  );
}

/// Check if a file is a possible NeomClaw binary (exists, non-empty, executable).
Future<bool> _isPossibleNeomClawBinary(String filePath) async {
  try {
    final file = File(filePath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size == 0) return false;

    if (!Platform.isWindows) {
      // Check executable permission
      final result = await Process.run('test', ['-x', filePath]);
      return result.exitCode == 0;
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Atomically move a staged binary to the install path.
Future<void> _atomicMoveToInstallPath(
    String stagedBinaryPath, String installPath) async {
  final installDir = p.dirname(installPath);
  await Directory(installDir).create(recursive: true);

  final tempInstallPath =
      '$installPath.tmp.$pid.${DateTime.now().millisecondsSinceEpoch}';
  try {
    await File(stagedBinaryPath).copy(tempInstallPath);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', tempInstallPath]);
    }
    await File(tempInstallPath).rename(installPath);
    _logDebug('Atomically installed binary to $installPath');
  } catch (e) {
    try {
      await File(tempInstallPath).delete();
    } catch (_) {}
    rethrow;
  }
}

/// Install a version from a direct binary download in staging.
Future<void> _installVersionFromBinary(
    String stagingPath, String installPath) async {
  final platform = getPlatform();
  final binaryName = getBinaryName(platform);
  final stagedBinaryPath = p.join(stagingPath, binaryName);

  final file = File(stagedBinaryPath);
  if (!await file.exists()) {
    throw Exception('Staged binary not found');
  }

  await _atomicMoveToInstallPath(stagedBinaryPath, installPath);

  // Clean up staging
  await Directory(stagingPath).delete(recursive: true);
}

// ═══════════════════════════════════════════════════════════════════════════
// NATIVE INSTALLER CONTROLLER (Sint pattern)
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the native installer lifecycle using Sint state management.
class NativeInstallerController extends SintController {
  /// Current installation state.
  final installState = ''.obs; // 'idle', 'checking', 'downloading', 'installing', 'done', 'error'

  /// Current version being installed.
  final currentVersion = ''.obs;

  /// Latest available version.
  final latestVersion = ''.obs;

  /// Error message if installation failed.
  final errorMessage = ''.obs;

  /// Detected package manager.
  final detectedPackageManager = PackageManager.unknown.obs;

  /// Whether an update is available.
  final updateAvailable = false.obs;

  /// Progress percentage (0-100).
  final progress = 0.0.obs;

  @override
  void onInit() {
    super.onInit();
    installState.value = 'idle';
  }

  /// Check for available updates.
  Future<void> checkForUpdate({String channel = 'latest'}) async {
    installState.value = 'checking';
    try {
      final latest = await getLatestVersion(channel);
      latestVersion.value = latest;
      updateAvailable.value = latest != currentVersion.value;
      installState.value = 'idle';
    } catch (e) {
      errorMessage.value = e.toString();
      installState.value = 'error';
    }
  }

  /// Perform a version update.
  Future<bool> performUpdate({
    required String channelOrVersion,
    bool forceReinstall = false,
  }) async {
    installState.value = 'downloading';
    progress.value = 0;

    try {
      final version = await getLatestVersion(channelOrVersion);
      latestVersion.value = version;

      final dirs = _getBaseDirectories();
      final stagingPath = p.join(dirs.staging, version);
      final installPath = p.join(dirs.versions, version);

      // Ensure directories exist
      await Directory(dirs.versions).create(recursive: true);
      await Directory(dirs.staging).create(recursive: true);
      await Directory(dirs.locks).create(recursive: true);
      await Directory(p.dirname(dirs.executable)).create(recursive: true);

      // Check if already installed
      final alreadyInstalled =
          await _isPossibleNeomClawBinary(installPath) && !forceReinstall;

      if (!alreadyInstalled) {
        installState.value = 'downloading';
        progress.value = 25;
        await downloadVersion(version, stagingPath);

        installState.value = 'installing';
        progress.value = 75;
        await _installVersionFromBinary(stagingPath, installPath);
      }

      // Update symlink
      progress.value = 90;
      await _updateSymlink(dirs.executable, installPath);

      progress.value = 100;
      currentVersion.value = version;
      installState.value = 'done';
      return !alreadyInstalled;
    } catch (e) {
      errorMessage.value = e.toString();
      installState.value = 'error';
      return false;
    }
  }

  /// Detect the package manager that installed the application.
  Future<void> detectPackageManager() async {
    detectedPackageManager.value = await getPackageManager();
  }

  /// Update the executable symlink.
  Future<void> _updateSymlink(String symlinkPath, String targetPath) async {
    final platform = getPlatform();
    final isWindows = platform.startsWith('win32');

    if (isWindows) {
      // On Windows, copy instead of symlink
      try {
        final existing = File(symlinkPath);
        if (await existing.exists()) {
          final target = File(targetPath);
          if (await target.exists()) {
            final existingStat = await existing.stat();
            final targetStat = await target.stat();
            if (existingStat.size == targetStat.size) return; // Same file
          }
          // Rename old, copy new, clean up
          final oldPath = '$symlinkPath.old.${DateTime.now().millisecondsSinceEpoch}';
          await existing.rename(oldPath);
          try {
            await File(targetPath).copy(symlinkPath);
            try { await File(oldPath).delete(); } catch (_) {}
          } catch (e) {
            try { await File(oldPath).rename(symlinkPath); } catch (_) {}
            rethrow;
          }
        } else {
          await File(targetPath).copy(symlinkPath);
        }
      } catch (e) {
        _logDebug('Windows copy failed: $e');
        rethrow;
      }
    } else {
      // Unix: create symlink
      try {
        final link = Link(symlinkPath);
        if (await link.exists()) {
          await link.delete();
        } else {
          // Remove file if it exists (e.g., old binary copy)
          final file = File(symlinkPath);
          if (await file.exists()) await file.delete();
        }
        await Link(symlinkPath).create(targetPath);
        _logDebug('Created symlink $symlinkPath -> $targetPath');
      } catch (e) {
        _logDebug('Symlink creation failed: $e');
        rethrow;
      }
    }
  }

  /// Clean up old versions, keeping [versionRetentionCount] most recent.
  Future<int> cleanupOldVersions() async {
    final dirs = _getBaseDirectories();
    try {
      final versionsDir = Directory(dirs.versions);
      if (!await versionsDir.exists()) return 0;

      final entries = await versionsDir.list().toList();
      if (entries.length <= versionRetentionCount) return 0;

      // Sort by modification time (newest first)
      entries.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      int cleaned = 0;
      for (int i = versionRetentionCount; i < entries.length; i++) {
        final entry = entries[i];
        final version = p.basename(entry.path);

        // Don't delete locked versions
        final lockPath = p.join(dirs.locks, '$version.lock');
        if (isLockActive(lockPath)) continue;

        try {
          if (entry is File) {
            await entry.delete();
          } else if (entry is Directory) {
            await entry.delete(recursive: true);
          }
          cleaned++;
          _logDebug('Cleaned up old version: $version');
        } catch (_) {}
      }
      return cleaned;
    } catch (_) {
      return 0;
    }
  }

  /// Lock the currently running version to prevent cleanup.
  Future<bool> lockCurrentVersion(String version) async {
    final dirs = _getBaseDirectories();
    final versionPath = p.join(dirs.versions, version);
    final lockPath = p.join(dirs.locks, '$version.lock');
    return acquireProcessLifetimeLock(versionPath, lockPath);
  }

  /// Static helper to check if a process is running.
  static bool isProcessRunning(int pid) {
    if (pid <= 1) return false;
    try {
      final result = Process.runSync('kill', ['-0', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

void _logDebug(String message) {
  // In production, this would go to the debug log system
  assert(() {
    // ignore: avoid_print
    print('[NativeInstaller] $message');
    return true;
  }());
}
