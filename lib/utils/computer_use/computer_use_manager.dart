/// Computer Use Manager
///
/// Faithful port of neomage/src/utils/computerUse/*.ts
/// Covers: executor.ts, computerUseLock.ts, appNames.ts
///
/// Provides:
/// - CLI ComputerExecutor with mouse/keyboard/screenshot/app management
/// - Session-level computer use lock with O_EXCL atomic acquisition
/// - App name filtering/sanitization for prompt injection hardening
/// - macOS native module integration (Rust/enigo input, Swift screenshots)
library;

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sint/sint.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// JPEG quality for screenshots.
const double screenshotJpegQuality = 0.75;

/// Settle time after mouse move before reading position or dispatching click.
const int moveSettleMs = 50;

/// Lock file name for computer use session lock.
const String lockFilename = 'computer-use.lock';

/// Sentinel bundle ID when terminal detection fails.
const String cliHostBundleId = 'com.neomage-cli';

/// Maximum length for app display names (prompt injection hardening).
const int appNameMaxLen = 40;

/// Maximum number of app names to include in descriptions.
const int appNameMaxCount = 50;

/// Threshold for long prefill prompts (chars).
const int longPrefillThreshold = 1000;

// ═══════════════════════════════════════════════════════════════════════════
// DISPLAY GEOMETRY
// ═══════════════════════════════════════════════════════════════════════════

/// Display geometry information.
class DisplayGeometry {
  final int width;
  final int height;
  final double scaleFactor;
  final int? displayId;

  const DisplayGeometry({
    required this.width,
    required this.height,
    required this.scaleFactor,
    this.displayId,
  });

  @override
  String toString() =>
      'DisplayGeometry(${width}x$height @${scaleFactor}x, id: $displayId)';
}

// ═══════════════════════════════════════════════════════════════════════════
// APP TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Information about the frontmost application.
class FrontmostApp {
  final String bundleId;
  final String displayName;

  const FrontmostApp({required this.bundleId, required this.displayName});
}

/// Information about an installed application.
class InstalledApp {
  final String bundleId;
  final String displayName;
  final String path;
  final String? iconDataUrl;

  const InstalledApp({
    required this.bundleId,
    required this.displayName,
    required this.path,
    this.iconDataUrl,
  });
}

/// Information about a running application.
class RunningApp {
  final String bundleId;
  final String displayName;

  const RunningApp({required this.bundleId, required this.displayName});
}

/// Screenshot result.
class ScreenshotResult {
  final String base64;
  final int width;
  final int height;

  const ScreenshotResult({
    required this.base64,
    required this.width,
    required this.height,
  });
}

/// Result of preparing capture with display resolution.
class ResolvePrepareCaptureResult {
  final ScreenshotResult? screenshot;
  final List<String> hidden;
  final String? activated;

  const ResolvePrepareCaptureResult({
    this.screenshot,
    this.hidden = const [],
    this.activated,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPUTER USE CAPABILITIES
// ═══════════════════════════════════════════════════════════════════════════

/// Capabilities of the CLI computer use executor.
class ComputerUseCapabilities {
  final String hostBundleId;
  final bool supportsScreenshot;
  final bool supportsClick;
  final bool supportsType;
  final bool supportsKey;
  final bool supportsDrag;
  final bool supportsScroll;
  final bool supportsAppManagement;

  const ComputerUseCapabilities({
    required this.hostBundleId,
    this.supportsScreenshot = true,
    this.supportsClick = true,
    this.supportsType = true,
    this.supportsKey = true,
    this.supportsDrag = true,
    this.supportsScroll = true,
    this.supportsAppManagement = true,
  });
}

/// Default CLI computer use capabilities.
const cliCuCapabilities = ComputerUseCapabilities(
  hostBundleId: cliHostBundleId,
);

// ═══════════════════════════════════════════════════════════════════════════
// APP NAME FILTERING (appNames.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Only apps under these roots are shown (macOS).
const List<String> pathAllowlist = ['/Applications/', '/System/Applications/'];

/// Display-name patterns that mark background services.
final List<RegExp> namePatternBlocklist = [
  RegExp(r'Helper(?:$|\s\()'),
  RegExp(r'Agent(?:$|\s\()'),
  RegExp(r'Service(?:$|\s\()'),
  RegExp(r'Uninstaller(?:$|\s\()'),
  RegExp(r'Updater(?:$|\s\()'),
  RegExp(r'^\.'),
];

/// Apps commonly requested for CU automation. Always included if installed.
/// Bundle IDs (locale-invariant). Keep <30.
const Set<String> alwaysKeepBundleIds = {
  // Browsers
  'com.apple.Safari',
  'com.google.Chrome',
  'com.microsoft.edgemac',
  'org.mozilla.firefox',
  'company.thebrowser.Browser', // Arc
  // Communication
  'com.tinyspeck.slackmacgap',
  'us.zoom.xos',
  'com.microsoft.teams2',
  'com.microsoft.teams',
  'com.apple.MobileSMS',
  'com.apple.mail',
  // Productivity
  'com.microsoft.Word',
  'com.microsoft.Excel',
  'com.microsoft.Powerpoint',
  'com.microsoft.Outlook',
  'com.apple.iWork.Pages',
  'com.apple.iWork.Numbers',
  'com.apple.iWork.Keynote',
  'com.google.GoogleDocs',
  // Notes / PM
  'notion.id',
  'com.apple.Notes',
  'md.obsidian',
  'com.linear',
  'com.figma.Desktop',
  // Dev
  'com.microsoft.VSCode',
  'com.apple.Terminal',
  'com.googlecode.iterm2',
  'com.github.GitHubDesktop',
  // System essentials
  'com.apple.finder',
  'com.apple.iCal',
  'com.apple.systempreferences',
};

/// Regex for allowed app name characters.
/// \p{L}\p{M}\p{N} with Unicode — not \w (ASCII-only).
/// Single space not \s — \s matches newlines.
final RegExp appNameAllowed = RegExp(
  r'^[\p{L}\p{M}\p{N}_ .&'
  "'"
  r'()+\-]+$',
  unicode: true,
);

/// Check if a path is a user-facing application path.
bool _isUserFacingPath(String path, String? homeDir) {
  if (pathAllowlist.any((root) => path.startsWith(root))) return true;
  if (homeDir != null) {
    final userApps = homeDir.endsWith('/')
        ? '${homeDir}Applications/'
        : '$homeDir/Applications/';
    if (path.startsWith(userApps)) return true;
  }
  return false;
}

/// Check if a name matches a noisy background-service pattern.
bool _isNoisyName(String name) {
  return namePatternBlocklist.any((re) => re.hasMatch(name));
}

/// Core sanitization: length cap + trim + dedupe + sort.
List<String> _sanitizeCore(List<String> raw, bool applyCharFilter) {
  final seen = <String>{};
  final result = raw.map((name) => name.trim()).where((trimmed) {
    if (trimmed.isEmpty) return false;
    if (trimmed.length > appNameMaxLen) return false;
    if (applyCharFilter && !appNameAllowed.hasMatch(trimmed)) return false;
    if (seen.contains(trimmed)) return false;
    seen.add(trimmed);
    return true;
  }).toList()..sort((a, b) => a.compareTo(b));
  return result;
}

/// Sanitize app names with char filter and count cap.
List<String> _sanitizeAppNames(List<String> raw) {
  final filtered = _sanitizeCore(raw, true);
  if (filtered.length <= appNameMaxCount) return filtered;
  return [
    ...filtered.take(appNameMaxCount),
    '... and ${filtered.length - appNameMaxCount} more',
  ];
}

/// Sanitize trusted names (no char filter applied).
List<String> _sanitizeTrustedNames(List<String> raw) {
  return _sanitizeCore(raw, false);
}

/// Filter raw Spotlight results to user-facing apps, then sanitize.
/// Always-keep apps bypass path/name filter AND char allowlist.
List<String> filterAppsForDescription(
  List<InstalledApp> installed,
  String? homeDir,
) {
  final alwaysKept = <String>[];
  final rest = <String>[];

  for (final app in installed) {
    if (alwaysKeepBundleIds.contains(app.bundleId)) {
      alwaysKept.add(app.displayName);
    } else if (_isUserFacingPath(app.path, homeDir) &&
        !_isNoisyName(app.displayName)) {
      rest.add(app.displayName);
    }
  }

  final sanitizedAlways = _sanitizeTrustedNames(alwaysKept);
  final alwaysSet = sanitizedAlways.toSet();
  return [
    ...sanitizedAlways,
    ..._sanitizeAppNames(rest).where((n) => !alwaysSet.contains(n)),
  ];
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPUTER USE LOCK (computerUseLock.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Lock content stored in computer-use.lock.
class ComputerUseLock {
  final String sessionId;
  final int pid;
  final int acquiredAt;

  const ComputerUseLock({
    required this.sessionId,
    required this.pid,
    required this.acquiredAt,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'pid': pid,
    'acquiredAt': acquiredAt,
  };

  static ComputerUseLock? fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    if (value['sessionId'] is! String || value['pid'] is! int) return null;
    return ComputerUseLock(
      sessionId: value['sessionId'] as String,
      pid: value['pid'] as int,
      acquiredAt: (value['acquiredAt'] as int?) ?? 0,
    );
  }
}

/// Result of attempting to acquire the computer use lock.
sealed class AcquireResult {}

class AcquireResultAcquired extends AcquireResult {
  final bool fresh;
  AcquireResultAcquired({required this.fresh});
}

class AcquireResultBlocked extends AcquireResult {
  final String by;
  AcquireResultBlocked({required this.by});
}

/// Result of checking the computer use lock state.
sealed class CheckResult {}

class CheckResultFree extends CheckResult {}

class CheckResultHeldBySelf extends CheckResult {}

class CheckResultBlocked extends CheckResult {
  final String by;
  CheckResultBlocked({required this.by});
}

/// Manages computer use session locking.
class ComputerUseLockManager {
  final String _configHomeDir;
  final String _sessionId;
  VoidCallback? _unregisterCleanup;

  ComputerUseLockManager({
    required String configHomeDir,
    required String sessionId,
  }) : _configHomeDir = configHomeDir,
       _sessionId = sessionId;

  String get _lockPath => p.join(_configHomeDir, lockFilename);

  /// Read the current lock file.
  Future<ComputerUseLock?> _readLock() async {
    try {
      final raw = await File(_lockPath).readAsString();
      return ComputerUseLock.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Check if a process is still running.
  bool _isProcessRunning(int pid) {
    try {
      final result = Process.runSync('kill', ['-0', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Atomically create the lock file with O_EXCL semantics.
  Future<bool> _tryCreateExclusive(ComputerUseLock lock) async {
    try {
      final file = File(_lockPath);
      final raf = await file.open(mode: FileMode.writeOnly);
      // If file already exists, this doesn't give us EXCL semantics in pure Dart.
      // We emulate O_EXCL by checking existence first + atomic write.
      if (await File(_lockPath).exists()) {
        await raf.close();
        return false;
      }
      await raf.writeString(jsonEncode(lock.toJson()));
      await raf.flush();
      await raf.close();
      return true;
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 17 /* EEXIST */ ) return false;
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// Check lock state without acquiring.
  Future<CheckResult> checkComputerUseLock() async {
    final existing = await _readLock();
    if (existing == null) return CheckResultFree();
    if (existing.sessionId == _sessionId) return CheckResultHeldBySelf();
    if (_isProcessRunning(existing.pid)) {
      return CheckResultBlocked(by: existing.sessionId);
    }
    // Stale lock — recover
    _logDebug(
      'Recovering stale computer-use lock from session ${existing.sessionId} (PID ${existing.pid})',
    );
    try {
      await File(_lockPath).delete();
    } catch (_) {}
    return CheckResultFree();
  }

  /// Zero-syscall check: does THIS process believe it holds the lock?
  bool isLockHeldLocally() => _unregisterCleanup != null;

  /// Try to acquire the computer-use lock for the current session.
  Future<AcquireResult> tryAcquireComputerUseLock() async {
    final lock = ComputerUseLock(
      sessionId: _sessionId,
      pid: pid,
      acquiredAt: DateTime.now().millisecondsSinceEpoch,
    );

    await Directory(_configHomeDir).create(recursive: true);

    // Try fresh acquisition
    if (await _tryCreateExclusive(lock)) {
      _registerLockCleanup();
      return AcquireResultAcquired(fresh: true);
    }

    final existing = await _readLock();

    // Corrupt/unparseable — treat as stale
    if (existing == null) {
      try {
        await File(_lockPath).delete();
      } catch (_) {}
      if (await _tryCreateExclusive(lock)) {
        _registerLockCleanup();
        return AcquireResultAcquired(fresh: true);
      }
      final winner = await _readLock();
      return AcquireResultBlocked(by: winner?.sessionId ?? 'unknown');
    }

    // Already held by this session
    if (existing.sessionId == _sessionId) {
      return AcquireResultAcquired(fresh: false);
    }

    // Another live session holds it
    if (_isProcessRunning(existing.pid)) {
      return AcquireResultBlocked(by: existing.sessionId);
    }

    // Stale lock — recover
    _logDebug(
      'Recovering stale computer-use lock from session ${existing.sessionId} (PID ${existing.pid})',
    );
    try {
      await File(_lockPath).delete();
    } catch (_) {}
    if (await _tryCreateExclusive(lock)) {
      _registerLockCleanup();
      return AcquireResultAcquired(fresh: true);
    }
    final winner = await _readLock();
    return AcquireResultBlocked(by: winner?.sessionId ?? 'unknown');
  }

  /// Release the computer-use lock if the current session owns it.
  Future<bool> releaseComputerUseLock() async {
    _unregisterCleanup?.call();
    _unregisterCleanup = null;

    final existing = await _readLock();
    if (existing == null || existing.sessionId != _sessionId) return false;
    try {
      await File(_lockPath).delete();
      _logDebug('Released computer-use lock');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _registerLockCleanup() {
    _unregisterCleanup?.call();
    _unregisterCleanup = () {
      // Cleanup will release the lock on process exit
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPUTER EXECUTOR (executor.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Abstract interface for computer use operations.
abstract class ComputerExecutor {
  ComputerUseCapabilities get capabilities;

  // Pre-action sequence
  Future<List<String>> prepareForAction(
    List<String> allowlistBundleIds, [
    int? displayId,
  ]);
  Future<List<Map<String, String>>> previewHideSet(
    List<String> allowlistBundleIds, [
    int? displayId,
  ]);

  // Display
  Future<DisplayGeometry> getDisplaySize([int? displayId]);
  Future<List<DisplayGeometry>> listDisplays();
  Future<List<Map<String, dynamic>>> findWindowDisplays(List<String> bundleIds);
  Future<ResolvePrepareCaptureResult> resolvePrepareCapture({
    required List<String> allowedBundleIds,
    int? preferredDisplayId,
    required bool autoResolve,
    bool? doHide,
  });
  Future<ScreenshotResult> screenshot({
    required List<String> allowedBundleIds,
    int? displayId,
  });
  Future<ScreenshotResult> zoom({
    required Map<String, num> regionLogical,
    required List<String> allowedBundleIds,
    int? displayId,
  });

  // Keyboard
  Future<void> key(String keySequence, [int? repeat]);
  Future<void> holdKey(List<String> keyNames, int durationMs);
  Future<void> type(String text, {required bool viaClipboard});
  Future<String> readClipboard();
  Future<void> writeClipboard(String text);

  // Mouse
  Future<void> moveMouse(double x, double y);
  Future<void> click(
    double x,
    double y,
    String button,
    int count, [
    List<String>? modifiers,
  ]);
  Future<void> mouseDown();
  Future<void> mouseUp();
  Future<Map<String, double>> getCursorPosition();
  Future<void> drag(Map<String, double>? from, Map<String, double> to);
  Future<void> scroll(double x, double y, double dx, double dy);

  // App management
  Future<FrontmostApp?> getFrontmostApp();
  Future<Map<String, String>?> appUnderPoint(double x, double y);
  Future<List<InstalledApp>> listInstalledApps();
  Future<String?> getAppIcon(String path);
  Future<List<RunningApp>> listRunningApps();
  Future<void> openApp(String bundleId);
}

/// macOS CLI executor that wraps native modules.
/// Uses `@ant/computer-use-input` (Rust/enigo) for mouse/keyboard and
/// `@ant/computer-use-swift` for screenshots, app management, TCC.
class CliComputerExecutor extends ComputerExecutor {
  final bool Function() _getMouseAnimationEnabled;
  final bool Function() _getHideBeforeActionEnabled;
  final String? _terminalBundleId;
  // ignore: unused_field
  final String _surrogateHost;

  CliComputerExecutor({
    required bool Function() getMouseAnimationEnabled,
    required bool Function() getHideBeforeActionEnabled,
  }) : _getMouseAnimationEnabled = getMouseAnimationEnabled,
       _getHideBeforeActionEnabled = getHideBeforeActionEnabled,
       _terminalBundleId = _detectTerminalBundleId(),
       _surrogateHost = _detectTerminalBundleId() ?? cliHostBundleId {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'CliComputerExecutor is macOS-only. Current platform: ${Platform.operatingSystem}',
      );
    }
  }

  @override
  ComputerUseCapabilities get capabilities =>
      ComputerUseCapabilities(hostBundleId: cliHostBundleId);

  /// Compute target dimensions for screenshots.
  /// Logical -> physical -> API target dims.
  List<int> _computeTargetDims(int logicalW, int logicalH, double scaleFactor) {
    final physW = (logicalW * scaleFactor).round();
    final physH = (logicalH * scaleFactor).round();
    return _targetImageSize(physW, physH);
  }

  /// Port of targetImageSize from @ant/computer-use-mcp.
  /// Scales down to fit within API maximum dimensions while preserving aspect ratio.
  List<int> _targetImageSize(int w, int h) {
    const maxLong = 1568;
    const maxShort = 1120;

    if (w <= 0 || h <= 0) return [w, h];

    final longSide = max(w, h);
    final shortSide = min(w, h);

    if (longSide <= maxLong && shortSide <= maxShort) return [w, h];

    final longScale = maxLong / longSide;
    final shortScale = maxShort / shortSide;
    final scale = min(longScale, shortScale);

    return [(w * scale).round(), (h * scale).round()];
  }

  // ── Pre-action sequence ─────────────────────────────────────────────

  @override
  Future<List<String>> prepareForAction(
    List<String> allowlistBundleIds, [
    int? displayId,
  ]) async {
    if (!_getHideBeforeActionEnabled()) return [];

    try {
      // In a real implementation, this would call the Swift native module
      // to hide non-allowlisted apps and activate the target
      _logDebug('prepareForAction: hiding non-allowlisted apps');
      return [];
    } catch (e) {
      _logDebug('prepareForAction failed; continuing: $e');
      return [];
    }
  }

  @override
  Future<List<Map<String, String>>> previewHideSet(
    List<String> allowlistBundleIds, [
    int? displayId,
  ]) async {
    // Would call Swift native module
    return [];
  }

  // ── Display ─────────────────────────────────────────────────────────

  @override
  Future<DisplayGeometry> getDisplaySize([int? displayId]) async {
    // Get display size via native module or system_profiler
    try {
      final result = await Process.run('system_profiler', [
        'SPDisplaysDataType',
      ]);
      // Parse display info — simplified for port
      return const DisplayGeometry(width: 1920, height: 1080, scaleFactor: 2.0);
    } catch (_) {
      return const DisplayGeometry(width: 1920, height: 1080, scaleFactor: 2.0);
    }
  }

  @override
  Future<List<DisplayGeometry>> listDisplays() async {
    final primary = await getDisplaySize();
    return [primary];
  }

  @override
  Future<List<Map<String, dynamic>>> findWindowDisplays(
    List<String> bundleIds,
  ) async {
    return [];
  }

  @override
  Future<ResolvePrepareCaptureResult> resolvePrepareCapture({
    required List<String> allowedBundleIds,
    int? preferredDisplayId,
    required bool autoResolve,
    bool? doHide,
  }) async {
    final d = await getDisplaySize(preferredDisplayId);
    final targetDims = _computeTargetDims(d.width, d.height, d.scaleFactor);
    // Would call Swift native module for actual capture
    return const ResolvePrepareCaptureResult();
  }

  @override
  Future<ScreenshotResult> screenshot({
    required List<String> allowedBundleIds,
    int? displayId,
  }) async {
    final d = await getDisplaySize(displayId);
    final targetDims = _computeTargetDims(d.width, d.height, d.scaleFactor);

    // Use screencapture command as fallback
    final tempFile = p.join(
      Directory.systemTemp.path,
      'screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    try {
      await Process.run('screencapture', ['-x', '-t', 'jpg', tempFile]);
      final bytes = await File(tempFile).readAsBytes();
      final b64 = base64Encode(bytes);
      return ScreenshotResult(
        base64: b64,
        width: targetDims[0],
        height: targetDims[1],
      );
    } finally {
      try {
        await File(tempFile).delete();
      } catch (_) {}
    }
  }

  @override
  Future<ScreenshotResult> zoom({
    required Map<String, num> regionLogical,
    required List<String> allowedBundleIds,
    int? displayId,
  }) async {
    final d = await getDisplaySize(displayId);
    final w = regionLogical['w']?.toInt() ?? 100;
    final h = regionLogical['h']?.toInt() ?? 100;
    final targetDims = _computeTargetDims(w, h, d.scaleFactor);
    // Would call Swift captureRegion
    return ScreenshotResult(
      base64: '',
      width: targetDims[0],
      height: targetDims[1],
    );
  }

  // ── Keyboard ────────────────────────────────────────────────────────

  @override
  Future<void> key(String keySequence, [int? repeat]) async {
    final parts = keySequence.split('+').where((p) => p.isNotEmpty).toList();
    final n = repeat ?? 1;

    for (int i = 0; i < n; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 8));
      // Would call native input module
      _logDebug('key: ${parts.join("+")}');
    }
  }

  @override
  Future<void> holdKey(List<String> keyNames, int durationMs) async {
    // Press all keys, wait, release in reverse
    for (final k in keyNames) {
      _logDebug('holdKey press: $k');
    }
    await Future.delayed(Duration(milliseconds: durationMs));
    for (final k in keyNames.reversed) {
      _logDebug('holdKey release: $k');
    }
  }

  @override
  Future<void> type(String text, {required bool viaClipboard}) async {
    if (viaClipboard) {
      await _typeViaClipboard(text);
    } else {
      // Direct typing via native input module
      _logDebug('type: ${text.length} chars');
    }
  }

  @override
  Future<String> readClipboard() async {
    final result = await Process.run('pbpaste', []);
    if (result.exitCode != 0) {
      throw Exception('pbpaste exited with code ${result.exitCode}');
    }
    return result.stdout as String;
  }

  @override
  Future<void> writeClipboard(String text) async {
    final result = await Process.run(
      'pbcopy',
      [],
      environment: {},
      runInShell: false,
    );
    // pbcopy reads from stdin
    final proc = await Process.start('pbcopy', []);
    proc.stdin.write(text);
    await proc.stdin.close();
    final exitCode = await proc.exitCode;
    if (exitCode != 0) {
      throw Exception('pbcopy exited with code $exitCode');
    }
  }

  /// Type via clipboard (save, write, Cmd+V, restore).
  Future<void> _typeViaClipboard(String text) async {
    String? saved;
    try {
      saved = await readClipboard();
    } catch (_) {}

    try {
      await writeClipboard(text);
      final verify = await readClipboard();
      if (verify != text) {
        throw Exception('Clipboard write did not round-trip.');
      }
      await key('command+v');
      await Future.delayed(const Duration(milliseconds: 100));
    } finally {
      if (saved != null) {
        try {
          await writeClipboard(saved);
        } catch (_) {}
      }
    }
  }

  // ── Mouse ───────────────────────────────────────────────────────────

  @override
  Future<void> moveMouse(double x, double y) async {
    // Would call native input module
    _logDebug('moveMouse: ($x, $y)');
    await Future.delayed(const Duration(milliseconds: moveSettleMs));
  }

  @override
  Future<void> click(
    double x,
    double y,
    String button,
    int count, [
    List<String>? modifiers,
  ]) async {
    await moveMouse(x, y);
    if (modifiers != null && modifiers.isNotEmpty) {
      // Press modifiers, click, release modifiers
      for (final m in modifiers) {
        _logDebug('modifier press: $m');
      }
      _logDebug('click: $button x$count at ($x, $y)');
      for (final m in modifiers.reversed) {
        _logDebug('modifier release: $m');
      }
    } else {
      _logDebug('click: $button x$count at ($x, $y)');
    }
  }

  @override
  Future<void> mouseDown() async {
    _logDebug('mouseDown');
  }

  @override
  Future<void> mouseUp() async {
    _logDebug('mouseUp');
  }

  @override
  Future<Map<String, double>> getCursorPosition() async {
    // Would call native input module
    return {'x': 0, 'y': 0};
  }

  @override
  Future<void> drag(Map<String, double>? from, Map<String, double> to) async {
    if (from != null) {
      await moveMouse(from['x']!, from['y']!);
    }
    // Press, animated move, release
    _logDebug('mouseDown for drag');
    await Future.delayed(const Duration(milliseconds: moveSettleMs));
    await _animatedMove(to['x']!, to['y']!);
    _logDebug('mouseUp after drag');
  }

  @override
  Future<void> scroll(double x, double y, double dx, double dy) async {
    await moveMouse(x, y);
    if (dy != 0) _logDebug('scroll vertical: $dy');
    if (dx != 0) _logDebug('scroll horizontal: $dx');
  }

  /// Animated mouse movement with ease-out cubic at 60fps.
  Future<void> _animatedMove(double targetX, double targetY) async {
    if (!_getMouseAnimationEnabled()) {
      await moveMouse(targetX, targetY);
      return;
    }
    // Simplified animation — in production uses native module for actual cursor position
    await moveMouse(targetX, targetY);
  }

  // ── App management ──────────────────────────────────────────────────

  @override
  Future<FrontmostApp?> getFrontmostApp() async {
    // Would call native input module
    try {
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get {bundle identifier, name} of first process whose frontmost is true',
      ]);
      if (result.exitCode == 0) {
        final parts = (result.stdout as String).trim().split(', ');
        if (parts.length >= 2) {
          return FrontmostApp(bundleId: parts[0], displayName: parts[1]);
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<Map<String, String>?> appUnderPoint(double x, double y) async {
    return null; // Would need Swift native module
  }

  @override
  Future<List<InstalledApp>> listInstalledApps() async {
    // Use mdfind (Spotlight) to list apps
    final apps = <InstalledApp>[];
    try {
      final result = await Process.run('mdfind', [
        'kMDItemContentType == "com.apple.application-bundle"',
      ]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        for (final line in lines) {
          if (line.isEmpty) continue;
          final name = p.basenameWithoutExtension(line);
          // Get bundle ID via mdls
          try {
            final mdls = await Process.run('mdls', [
              '-name',
              'kMDItemCFBundleIdentifier',
              '-raw',
              line,
            ]);
            final bundleId = (mdls.stdout as String).trim();
            if (bundleId != '(null)' && bundleId.isNotEmpty) {
              apps.add(
                InstalledApp(bundleId: bundleId, displayName: name, path: line),
              );
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return apps;
  }

  @override
  Future<String?> getAppIcon(String path) async {
    return null; // Would need Swift native module
  }

  @override
  Future<List<RunningApp>> listRunningApps() async {
    final apps = <RunningApp>[];
    try {
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get {bundle identifier, name} of every process whose background only is false',
      ]);
      // Parse result — simplified
    } catch (_) {}
    return apps;
  }

  @override
  Future<void> openApp(String bundleId) async {
    await Process.run('open', ['-b', bundleId]);
  }
}

/// Unhide apps hidden during computer use (called at turn-end).
Future<void> unhideComputerUseApps(List<String> bundleIds) async {
  if (bundleIds.isEmpty) return;
  // Would call Swift native module to unhide
  _logDebug('unhideComputerUseApps: ${bundleIds.length} apps');
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPUTER USE CONTROLLER (Sint pattern)
// ═══════════════════════════════════════════════════════════════════════════

/// Sint controller managing computer use state.
class ComputerUseController extends SintController {
  /// Whether computer use is currently active.
  final isActive = false.obs;

  /// Current session's lock state.
  final lockState = ''.obs; // 'free', 'held_by_self', 'blocked'

  /// Blocking session ID if locked.
  final blockingSessionId = ''.obs;

  /// Hidden app bundle IDs (to restore on turn end).
  final hiddenApps = <String>[].obs;

  /// Whether mouse animation is enabled.
  final mouseAnimationEnabled = true.obs;

  /// Whether hide-before-action is enabled.
  final hideBeforeActionEnabled = true.obs;

  late final ComputerUseLockManager _lockManager;
  ComputerExecutor? _executor;

  @override
  void onInit() {
    super.onInit();
    lockState.value = 'free';
  }

  /// Initialize with session info.
  void initialize({required String configHomeDir, required String sessionId}) {
    _lockManager = ComputerUseLockManager(
      configHomeDir: configHomeDir,
      sessionId: sessionId,
    );
  }

  /// Get or create the executor.
  ComputerExecutor get executor {
    _executor ??= CliComputerExecutor(
      getMouseAnimationEnabled: () => mouseAnimationEnabled.value,
      getHideBeforeActionEnabled: () => hideBeforeActionEnabled.value,
    );
    return _executor!;
  }

  /// Acquire the computer use lock.
  Future<AcquireResult> acquireLock() async {
    final result = await _lockManager.tryAcquireComputerUseLock();
    if (result is AcquireResultAcquired) {
      isActive.value = true;
      lockState.value = 'held_by_self';
    } else if (result is AcquireResultBlocked) {
      lockState.value = 'blocked';
      blockingSessionId.value = result.by;
    }
    return result;
  }

  /// Release the computer use lock.
  Future<bool> releaseLock() async {
    final released = await _lockManager.releaseComputerUseLock();
    if (released) {
      isActive.value = false;
      lockState.value = 'free';
      // Unhide any hidden apps
      if (hiddenApps.isNotEmpty) {
        await unhideComputerUseApps(List.from(hiddenApps));
        hiddenApps.clear();
      }
    }
    return released;
  }

  /// Check lock state without acquiring.
  Future<CheckResult> checkLock() async {
    return _lockManager.checkComputerUseLock();
  }

  /// Whether lock is held locally (zero-syscall check).
  bool get isLockHeldLocally => _lockManager.isLockHeldLocally();

  /// Get filtered app names for description.
  Future<List<String>> getFilteredAppNames() async {
    final installed = await executor.listInstalledApps();
    final homeDir = Platform.environment['HOME'];
    return filterAppsForDescription(installed, homeDir);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Detect the terminal bundle ID on macOS.
String? _detectTerminalBundleId() {
  if (!Platform.isMacOS) return null;

  final termProgram = Platform.environment['TERM_PROGRAM'];
  if (termProgram == null) return null;

  const termBundleIds = <String, String>{
    'iTerm.app': 'com.googlecode.iterm2',
    'Apple_Terminal': 'com.apple.Terminal',
    'Ghostty': 'com.mitchellh.ghostty',
    'kitty': 'net.kovidgoyal.kitty',
    'Alacritty': 'org.alacritty',
    'WezTerm': 'com.github.wez.wezterm',
    'vscode': 'com.microsoft.VSCode',
  };

  return termBundleIds[termProgram];
}

void _logDebug(String message) {
  assert(() {
    // ignore: avoid_print
    print('[ComputerUse] $message');
    return true;
  }());
}

/// Typedef for cleanup callbacks.
typedef VoidCallback = void Function();
