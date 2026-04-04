/// IDE detection, integration helpers, path conversion.
///
/// Ported from openneomclaw/src/utils/ide.ts (1494 LOC).
library;

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// IDE type definitions
// ---------------------------------------------------------------------------

/// Supported IDE types.
enum IdeType {
  cursor,
  windsurf,
  vscode,
  pycharm,
  intellij,
  webstorm,
  phpstorm,
  rubymine,
  clion,
  goland,
  rider,
  datagrip,
  appcode,
  dataspell,
  aqua,
  gateway,
  fleet,
  androidstudio,
}

/// IDE kind categorization.
enum IdeKind { vscode, jetbrains }

/// Configuration for a supported IDE.
class IdeConfig {
  final IdeKind ideKind;
  final String displayName;
  final List<String> processKeywordsMac;
  final List<String> processKeywordsWindows;
  final List<String> processKeywordsLinux;

  const IdeConfig({
    required this.ideKind,
    required this.displayName,
    this.processKeywordsMac = const [],
    this.processKeywordsWindows = const [],
    this.processKeywordsLinux = const [],
  });
}

/// All supported IDE configurations.
const Map<IdeType, IdeConfig> supportedIdeConfigs = {
  IdeType.cursor: IdeConfig(
    ideKind: IdeKind.vscode,
    displayName: 'Cursor',
    processKeywordsMac: ['Cursor Helper', 'Cursor.app'],
    processKeywordsWindows: ['cursor.exe'],
    processKeywordsLinux: ['cursor'],
  ),
  IdeType.windsurf: IdeConfig(
    ideKind: IdeKind.vscode,
    displayName: 'Windsurf',
    processKeywordsMac: ['Windsurf Helper', 'Windsurf.app'],
    processKeywordsWindows: ['windsurf.exe'],
    processKeywordsLinux: ['windsurf'],
  ),
  IdeType.vscode: IdeConfig(
    ideKind: IdeKind.vscode,
    displayName: 'VS Code',
    processKeywordsMac: ['Visual Studio Code', 'Code Helper'],
    processKeywordsWindows: ['code.exe'],
    processKeywordsLinux: ['code'],
  ),
  IdeType.intellij: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'IntelliJ IDEA',
    processKeywordsMac: ['IntelliJ IDEA'],
    processKeywordsWindows: ['idea64.exe'],
    processKeywordsLinux: ['idea', 'intellij'],
  ),
  IdeType.pycharm: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'PyCharm',
    processKeywordsMac: ['PyCharm'],
    processKeywordsWindows: ['pycharm64.exe'],
    processKeywordsLinux: ['pycharm'],
  ),
  IdeType.webstorm: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'WebStorm',
    processKeywordsMac: ['WebStorm'],
    processKeywordsWindows: ['webstorm64.exe'],
    processKeywordsLinux: ['webstorm'],
  ),
  IdeType.phpstorm: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'PhpStorm',
    processKeywordsMac: ['PhpStorm'],
    processKeywordsWindows: ['phpstorm64.exe'],
    processKeywordsLinux: ['phpstorm'],
  ),
  IdeType.rubymine: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'RubyMine',
    processKeywordsMac: ['RubyMine'],
    processKeywordsWindows: ['rubymine64.exe'],
    processKeywordsLinux: ['rubymine'],
  ),
  IdeType.clion: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'CLion',
    processKeywordsMac: ['CLion'],
    processKeywordsWindows: ['clion64.exe'],
    processKeywordsLinux: ['clion'],
  ),
  IdeType.goland: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'GoLand',
    processKeywordsMac: ['GoLand'],
    processKeywordsWindows: ['goland64.exe'],
    processKeywordsLinux: ['goland'],
  ),
  IdeType.rider: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'Rider',
    processKeywordsMac: ['Rider'],
    processKeywordsWindows: ['rider64.exe'],
    processKeywordsLinux: ['rider'],
  ),
  IdeType.datagrip: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'DataGrip',
    processKeywordsMac: ['DataGrip'],
    processKeywordsWindows: ['datagrip64.exe'],
    processKeywordsLinux: ['datagrip'],
  ),
  IdeType.appcode: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'AppCode',
    processKeywordsMac: ['AppCode'],
    processKeywordsWindows: ['appcode.exe'],
    processKeywordsLinux: ['appcode'],
  ),
  IdeType.dataspell: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'DataSpell',
    processKeywordsMac: ['DataSpell'],
    processKeywordsWindows: ['dataspell64.exe'],
    processKeywordsLinux: ['dataspell'],
  ),
  IdeType.aqua: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'Aqua',
    processKeywordsMac: [],
    processKeywordsWindows: ['aqua64.exe'],
    processKeywordsLinux: [],
  ),
  IdeType.gateway: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'Gateway',
    processKeywordsMac: [],
    processKeywordsWindows: ['gateway64.exe'],
    processKeywordsLinux: [],
  ),
  IdeType.fleet: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'Fleet',
    processKeywordsMac: [],
    processKeywordsWindows: ['fleet.exe'],
    processKeywordsLinux: [],
  ),
  IdeType.androidstudio: IdeConfig(
    ideKind: IdeKind.jetbrains,
    displayName: 'Android Studio',
    processKeywordsMac: ['Android Studio'],
    processKeywordsWindows: ['studio64.exe'],
    processKeywordsLinux: ['android-studio'],
  ),
};

// ---------------------------------------------------------------------------
// IDE type helpers
// ---------------------------------------------------------------------------

/// Check if an IDE type is a VSCode variant.
bool isVSCodeIde(IdeType? ide) {
  if (ide == null) return false;
  final config = supportedIdeConfigs[ide];
  return config != null && config.ideKind == IdeKind.vscode;
}

/// Check if an IDE type is a JetBrains variant.
bool isJetBrainsIde(IdeType? ide) {
  if (ide == null) return false;
  final config = supportedIdeConfigs[ide];
  return config != null && config.ideKind == IdeKind.jetbrains;
}

// ---------------------------------------------------------------------------
// Lockfile types
// ---------------------------------------------------------------------------

/// JSON content of an IDE lockfile.
class LockfileJsonContent {
  final List<String>? workspaceFolders;
  final int? pid;
  final String? ideName;
  final String? transport;
  final bool? runningInWindows;
  final String? authToken;

  const LockfileJsonContent({
    this.workspaceFolders,
    this.pid,
    this.ideName,
    this.transport,
    this.runningInWindows,
    this.authToken,
  });

  factory LockfileJsonContent.fromJson(Map<String, dynamic> json) {
    return LockfileJsonContent(
      workspaceFolders: (json['workspaceFolders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      pid: json['pid'] as int?,
      ideName: json['ideName'] as String?,
      transport: json['transport'] as String?,
      runningInWindows: json['runningInWindows'] as bool?,
      authToken: json['authToken'] as String?,
    );
  }
}

/// Parsed IDE lockfile information.
class IdeLockfileInfo {
  final List<String> workspaceFolders;
  final int port;
  final int? pid;
  final String? ideName;
  final bool useWebSocket;
  final bool runningInWindows;
  final String? authToken;

  const IdeLockfileInfo({
    required this.workspaceFolders,
    required this.port,
    this.pid,
    this.ideName,
    this.useWebSocket = false,
    this.runningInWindows = false,
    this.authToken,
  });
}

/// Detected IDE info.
class DetectedIDEInfo {
  final String name;
  final int port;
  final List<String> workspaceFolders;
  final String url;
  final bool isValid;
  final String? authToken;
  final bool? ideRunningInWindows;

  const DetectedIDEInfo({
    required this.name,
    required this.port,
    required this.workspaceFolders,
    required this.url,
    required this.isValid,
    this.authToken,
    this.ideRunningInWindows,
  });
}

/// IDE extension installation status.
class IDEExtensionInstallationStatus {
  final bool installed;
  final String? error;
  final String? installedVersion;
  final IdeType? ideType;

  const IDEExtensionInstallationStatus({
    required this.installed,
    this.error,
    this.installedVersion,
    this.ideType,
  });
}

// ---------------------------------------------------------------------------
// Windows-to-WSL path conversion
// ---------------------------------------------------------------------------

/// Converts Windows paths to WSL-accessible local paths.
class WindowsToWSLConverter {
  final String? wslDistroName;

  const WindowsToWSLConverter(this.wslDistroName);

  /// Convert a Windows path to a WSL local path.
  String toLocalPath(String windowsPath) {
    // Handle UNC paths for WSL (\\wsl$\distro\...)
    final wslUncMatch =
        RegExp(r'^\\\\wsl\$\\([^\\]+)\\(.*)$', caseSensitive: false)
            .firstMatch(windowsPath);
    if (wslUncMatch != null) {
      final path = wslUncMatch.group(2)!.replaceAll('\\', '/');
      return '/$path';
    }

    // Handle \\wsl.localhost\ paths
    final wslLocalhostMatch =
        RegExp(r'^\\\\wsl\.localhost\\([^\\]+)\\(.*)$', caseSensitive: false)
            .firstMatch(windowsPath);
    if (wslLocalhostMatch != null) {
      final path = wslLocalhostMatch.group(2)!.replaceAll('\\', '/');
      return '/$path';
    }

    // Handle standard Windows drive paths (C:\Users\...)
    final driveMatch = RegExp(r'^([a-zA-Z]):\\(.*)$').firstMatch(windowsPath);
    if (driveMatch != null) {
      final drive = driveMatch.group(1)!.toLowerCase();
      final path = driveMatch.group(2)!.replaceAll('\\', '/');
      return '/mnt/$drive/$path';
    }

    return windowsPath;
  }
}

/// Check if a WSL path belongs to a specific distro.
bool checkWSLDistroMatch(String path, String distroName) {
  // Check \\wsl$\distro paths
  final wslMatch =
      RegExp(r'^\\\\wsl\$\\([^\\]+)', caseSensitive: false).firstMatch(path);
  if (wslMatch != null) {
    return wslMatch.group(1)!.toLowerCase() == distroName.toLowerCase();
  }

  // Check \\wsl.localhost\distro paths
  final localhostMatch =
      RegExp(r'^\\\\wsl\.localhost\\([^\\]+)', caseSensitive: false)
          .firstMatch(path);
  if (localhostMatch != null) {
    return localhostMatch.group(1)!.toLowerCase() == distroName.toLowerCase();
  }

  // Non-WSL paths are always valid
  return true;
}

// ---------------------------------------------------------------------------
// Editor display names
// ---------------------------------------------------------------------------

const Map<String, String> _editorDisplayNames = {
  'code': 'VS Code',
  'cursor': 'Cursor',
  'windsurf': 'Windsurf',
  'antigravity': 'Antigravity',
  'vi': 'Vim',
  'vim': 'Vim',
  'nano': 'nano',
  'notepad': 'Notepad',
  'start /wait notepad': 'Notepad',
  'emacs': 'Emacs',
  'subl': 'Sublime Text',
  'atom': 'Atom',
};

/// Convert a terminal name to a display-friendly IDE name.
String toIDEDisplayName(String? terminal) {
  if (terminal == null) return 'IDE';

  // Check supported IDE configs
  for (final entry in supportedIdeConfigs.entries) {
    if (entry.key.name == terminal) {
      return entry.value.displayName;
    }
  }

  // Check editor command names (exact match first)
  final editorName = _editorDisplayNames[terminal.toLowerCase().trim()];
  if (editorName != null) return editorName;

  // Extract command name from path/arguments
  final command = terminal.split(' ').first;
  final commandName = command.split('/').last.toLowerCase();
  final mappedName = _editorDisplayNames[commandName];
  if (mappedName != null) return mappedName;

  // Fallback: capitalize the command basename
  if (commandName.isNotEmpty) {
    return commandName[0].toUpperCase() + commandName.substring(1);
  }
  return terminal;
}

// ---------------------------------------------------------------------------
// IdeUtils SintController
// ---------------------------------------------------------------------------

/// Manages IDE detection, extension installation, and integration.
class IdeUtils extends SintController {
  /// Cached IDE detection results.
  final RxList<IdeType> cachedRunningIDEs = <IdeType>[].obs;
  final RxBool hasCachedResults = false.obs;

  /// Current IDE search abort controller.
  Completer<void>? _currentSearchAbort;

  /// Path to the neomclaw config home directory.
  String Function() _getNeomClawConfigHomeDir =
      () => '${Platform.environment['HOME'] ?? ''}/.neomclaw';

  /// Get the original CWD for workspace matching.
  String Function() _getOriginalCwd = () => Directory.current.path;

  /// Logging callback.
  void Function(String message, {String? level}) _logForDebugging =
      (message, {level}) {};

  /// Event logging callback.
  void Function(String event, Map<String, dynamic> data) _logEvent =
      (event, data) {};

  /// Error logging callback.
  void Function(Object error) _logError = (error) {};

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  void configure({
    String Function()? getNeomClawConfigHomeDir,
    String Function()? getOriginalCwd,
    void Function(String, {String? level})? logForDebugging,
    void Function(String, Map<String, dynamic>)? logEvent,
    void Function(Object)? logError,
  }) {
    if (getNeomClawConfigHomeDir != null) {
      _getNeomClawConfigHomeDir = getNeomClawConfigHomeDir;
    }
    if (getOriginalCwd != null) _getOriginalCwd = getOriginalCwd;
    if (logForDebugging != null) _logForDebugging = logForDebugging;
    if (logEvent != null) _logEvent = logEvent;
    if (logError != null) _logError = logError;
  }

  // ---------------------------------------------------------------------------
  // IDE lockfile management
  // ---------------------------------------------------------------------------

  /// Gets the potential IDE lockfiles directories path based on platform.
  Future<List<String>> getIdeLockfilesPaths() async {
    final paths = <String>['${_getNeomClawConfigHomeDir()}/ide'];

    if (Platform.isLinux) {
      // Check for WSL
      final wslDistro = Platform.environment['WSL_DISTRO_NAME'];
      if (wslDistro != null) {
        // Try to find Windows user profiles
        try {
          final usersDir = Directory('/mnt/c/Users');
          if (await usersDir.exists()) {
            await for (final user in usersDir.list()) {
              if (user is! Directory) continue;
              final name = user.path.split('/').last;
              if (['Public', 'Default', 'Default User', 'All Users']
                  .contains(name)) {
                continue;
              }
              paths.add('${user.path}/.neomclaw/ide');
            }
          }
        } catch (_) {
          // Expected on non-WSL or when C: isn't mounted
        }
      }
    }
    return paths;
  }

  /// Gets sorted IDE lockfiles from ~/.neomclaw/ide directory.
  Future<List<String>> getSortedIdeLockfiles() async {
    try {
      final ideLockFilePaths = await getIdeLockfilesPaths();

      final allLockfiles = <({String path, DateTime mtime})>[];

      for (final ideLockFilePath in ideLockFilePaths) {
        try {
          final dir = Directory(ideLockFilePath);
          if (!await dir.exists()) continue;

          await for (final file in dir.list()) {
            if (file is File && file.path.endsWith('.lock')) {
              try {
                final stat = await file.stat();
                allLockfiles.add((path: file.path, mtime: stat.modified));
              } catch (_) {}
            }
          }
        } catch (e) {
          _logError(e);
        }
      }

      // Sort by modification time (newest first)
      allLockfiles.sort((a, b) => b.mtime.compareTo(a.mtime));
      return allLockfiles.map((f) => f.path).toList();
    } catch (e) {
      _logError(e);
      return [];
    }
  }

  /// Read and parse an IDE lockfile.
  Future<IdeLockfileInfo?> readIdeLockfile(String path) async {
    try {
      final content = await File(path).readAsString();

      List<String> workspaceFolders = [];
      int? pid;
      String? ideName;
      bool useWebSocket = false;
      bool runningInWindows = false;
      String? authToken;

      try {
        final parsed = jsonDecode(content) as Map<String, dynamic>;
        final jsonContent = LockfileJsonContent.fromJson(parsed);
        workspaceFolders = jsonContent.workspaceFolders ?? [];
        pid = jsonContent.pid;
        ideName = jsonContent.ideName;
        useWebSocket = jsonContent.transport == 'ws';
        runningInWindows = jsonContent.runningInWindows ?? false;
        authToken = jsonContent.authToken;
      } catch (_) {
        // Older format - just a list of paths
        workspaceFolders = content.split('\n').map((l) => l.trim()).toList();
      }

      // Extract port from filename
      final filename = path.split(Platform.pathSeparator).last;
      final portStr = filename.replaceAll('.lock', '');
      final port = int.tryParse(portStr);
      if (port == null) return null;

      return IdeLockfileInfo(
        workspaceFolders: workspaceFolders,
        port: port,
        pid: pid,
        ideName: ideName,
        useWebSocket: useWebSocket,
        runningInWindows: runningInWindows,
        authToken: authToken,
      );
    } catch (e) {
      _logError(e);
      return null;
    }
  }

  /// Check if an IDE connection is responding by testing if the port is open.
  Future<bool> checkIdeConnection(
    String host,
    int port, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Check if a process is running by PID.
  bool isProcessRunning(int pid) {
    try {
      return Process.killPid(pid, ProcessSignal.sigcont);
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // IDE lockfile cleanup
  // ---------------------------------------------------------------------------

  /// Cleans up stale IDE lockfiles.
  Future<void> cleanupStaleIdeLockfiles() async {
    try {
      final lockfiles = await getSortedIdeLockfiles();

      for (final lockfilePath in lockfiles) {
        final lockfileInfo = await readIdeLockfile(lockfilePath);

        if (lockfileInfo == null) {
          try {
            await File(lockfilePath).delete();
          } catch (e) {
            _logError(e);
          }
          continue;
        }

        final host =
            await detectHostIP(lockfileInfo.runningInWindows, lockfileInfo.port);
        bool shouldDelete = false;

        if (lockfileInfo.pid != null) {
          if (!isProcessRunning(lockfileInfo.pid!)) {
            shouldDelete = true;
          }
        } else {
          final isResponding =
              await checkIdeConnection(host, lockfileInfo.port);
          if (!isResponding) {
            shouldDelete = true;
          }
        }

        if (shouldDelete) {
          try {
            await File(lockfilePath).delete();
          } catch (e) {
            _logError(e);
          }
        }
      }
    } catch (e) {
      _logError(e);
    }
  }

  // ---------------------------------------------------------------------------
  // IDE detection
  // ---------------------------------------------------------------------------

  /// Detects IDEs that have a running extension/plugin.
  Future<List<DetectedIDEInfo>> detectIDEs({
    bool includeInvalid = false,
  }) async {
    final detectedIDEs = <DetectedIDEInfo>[];

    try {
      final cwd = _getOriginalCwd();
      final lockfiles = await getSortedIdeLockfiles();
      final lockfileInfos =
          await Future.wait(lockfiles.map(readIdeLockfile));

      for (final lockfileInfo in lockfileInfos) {
        if (lockfileInfo == null) continue;

        // Check workspace folder match
        bool isValid = false;
        for (final idePath in lockfileInfo.workspaceFolders) {
          if (idePath.isEmpty) continue;
          final resolvedPath = Uri.parse(idePath).toFilePath();
          if (cwd == resolvedPath || cwd.startsWith('$resolvedPath/')) {
            isValid = true;
            break;
          }
        }

        if (!isValid && !includeInvalid) continue;

        final host = await detectHostIP(
          lockfileInfo.runningInWindows,
          lockfileInfo.port,
        );
        final url = lockfileInfo.useWebSocket
            ? 'ws://$host:${lockfileInfo.port}'
            : 'http://$host:${lockfileInfo.port}/sse';

        detectedIDEs.add(DetectedIDEInfo(
          url: url,
          name: lockfileInfo.ideName ?? 'IDE',
          workspaceFolders: lockfileInfo.workspaceFolders,
          port: lockfileInfo.port,
          isValid: isValid,
          authToken: lockfileInfo.authToken,
          ideRunningInWindows: lockfileInfo.runningInWindows,
        ));
      }
    } catch (e) {
      _logError(e);
    }

    return detectedIDEs;
  }

  /// Finds an available IDE with polling.
  Future<DetectedIDEInfo?> findAvailableIDE({
    Duration timeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    _currentSearchAbort?.complete();
    final abort = Completer<void>();
    _currentSearchAbort = abort;

    await cleanupStaleIdeLockfiles();
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout && !abort.isCompleted) {
      final ides = await detectIDEs();
      if (abort.isCompleted) return null;
      if (ides.length == 1) return ides.first;
      await Future.delayed(pollInterval);
    }
    return null;
  }

  /// Detects running IDEs by process inspection.
  Future<List<IdeType>> detectRunningIDEs() async {
    final runningIDEs = <IdeType>[];

    try {
      if (Platform.isMacOS) {
        final result = await Process.run('bash', [
          '-c',
          'ps aux | grep -E "Visual Studio Code|Code Helper|Cursor Helper|Windsurf Helper|IntelliJ IDEA|PyCharm|WebStorm|PhpStorm|RubyMine|CLion|GoLand|Rider|DataGrip|AppCode|DataSpell|Android Studio" | grep -v grep',
        ]);
        final stdout = result.stdout as String? ?? '';

        for (final entry in supportedIdeConfigs.entries) {
          for (final keyword in entry.value.processKeywordsMac) {
            if (stdout.contains(keyword)) {
              runningIDEs.add(entry.key);
              break;
            }
          }
        }
      } else if (Platform.isLinux) {
        final result = await Process.run('bash', [
          '-c',
          'ps aux | grep -E "code|cursor|windsurf|idea|pycharm|webstorm|phpstorm|rubymine|clion|goland|rider|datagrip|dataspell|android-studio" | grep -v grep',
        ]);
        final stdout = (result.stdout as String? ?? '').toLowerCase();

        for (final entry in supportedIdeConfigs.entries) {
          for (final keyword in entry.value.processKeywordsLinux) {
            if (stdout.contains(keyword)) {
              if (entry.key != IdeType.vscode) {
                runningIDEs.add(entry.key);
                break;
              } else if (!stdout.contains('cursor') &&
                  !stdout.contains('appcode')) {
                runningIDEs.add(entry.key);
                break;
              }
            }
          }
        }
      }
    } catch (e) {
      _logError(e);
    }

    cachedRunningIDEs.value = runningIDEs;
    hasCachedResults.value = true;
    return runningIDEs;
  }

  /// Returns cached IDE detection results, or performs detection if cache is empty.
  Future<List<IdeType>> detectRunningIDEsCached() async {
    if (!hasCachedResults.value) {
      return detectRunningIDEs();
    }
    return cachedRunningIDEs.toList();
  }

  /// Resets the cache for detectRunningIDEsCached.
  void resetDetectRunningIDEs() {
    cachedRunningIDEs.clear();
    hasCachedResults.value = false;
  }

  // ---------------------------------------------------------------------------
  // IDE extension checks
  // ---------------------------------------------------------------------------

  /// Check if cursor IDE is installed.
  Future<bool> isCursorInstalled() async {
    try {
      final result = await Process.run('cursor', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Check if Windsurf IDE is installed.
  Future<bool> isWindsurfInstalled() async {
    try {
      final result = await Process.run('windsurf', ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Check if VS Code is installed.
  Future<bool> isVSCodeInstalled() async {
    try {
      final result = await Process.run('code', ['--help']);
      return result.exitCode == 0 &&
          (result.stdout as String?)?.contains('Visual Studio Code') == true;
    } catch (_) {
      return false;
    }
  }

  /// Check if the IDE extension is installed for a given IDE type.
  Future<bool> isIDEExtensionInstalled(
    IdeType ideType, {
    String extensionId = 'anthropic.neom-claw',
  }) async {
    if (isVSCodeIde(ideType)) {
      final command = getVSCodeIDECommand(ideType);
      if (command != null) {
        try {
          final result = await Process.run(command, ['--list-extensions']);
          return (result.stdout as String?)?.contains(extensionId) == true;
        } catch (_) {}
      }
    }
    return false;
  }

  /// Get the VSCode CLI command for a given IDE type.
  String? getVSCodeIDECommand(IdeType ideType) {
    switch (ideType) {
      case IdeType.vscode:
        return 'code';
      case IdeType.cursor:
        return 'cursor';
      case IdeType.windsurf:
        return 'windsurf';
      default:
        return null;
    }
  }

  /// Get the installed VSCode extension version.
  Future<String?> getInstalledVSCodeExtensionVersion(String command) async {
    try {
      final result =
          await Process.run(command, ['--list-extensions', '--show-versions']);
      final lines = (result.stdout as String?)?.split('\n') ?? [];
      for (final line in lines) {
        final parts = line.split('@');
        if (parts.length == 2 && parts[0] == 'anthropic.neom-claw') {
          return parts[1];
        }
      }
    } catch (_) {}
    return null;
  }

  /// Attempt to install the IDE extension.
  Future<IDEExtensionInstallationStatus?> maybeInstallIDEExtension(
    IdeType ideType,
  ) async {
    try {
      if (isVSCodeIde(ideType)) {
        final command = getVSCodeIDECommand(ideType);
        if (command != null) {
          final result = await Process.run(
            command,
            ['--force', '--install-extension', 'anthropic.neom-claw'],
          );
          if (result.exitCode != 0) {
            throw Exception('${result.exitCode}: ${result.stderr}');
          }
          _logEvent('tengu_ext_installed', {});
          return IDEExtensionInstallationStatus(
            installed: true,
            ideType: ideType,
          );
        }
      }
      return null;
    } catch (e) {
      _logEvent('tengu_ext_install_error', {});
      _logError(e);
      return IDEExtensionInstallationStatus(
        installed: false,
        error: e.toString(),
        ideType: ideType,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // IDE client helpers
  // ---------------------------------------------------------------------------

  /// Check if there is an IDE extension connected with diff support.
  bool hasAccessToIDEExtensionDiffFeature(
    List<Map<String, dynamic>> mcpClients,
  ) {
    return mcpClients.any(
      (client) =>
          client['type'] == 'connected' && client['name'] == 'ide',
    );
  }

  /// Gets the connected IDE name from MCP clients.
  String? getConnectedIdeName(List<Map<String, dynamic>> mcpClients) {
    final ideClient = mcpClients.firstWhere(
      (client) => client['type'] == 'connected' && client['name'] == 'ide',
      orElse: () => <String, dynamic>{},
    );
    return getIdeClientName(ideClient);
  }

  /// Get IDE client name from config.
  String? getIdeClientName(Map<String, dynamic>? ideClient) {
    if (ideClient == null || ideClient.isEmpty) return null;
    final config = ideClient['config'] as Map<String, dynamic>?;
    if (config == null) return null;
    final type = config['type'] as String?;
    if (type == 'sse-ide' || type == 'ws-ide') {
      return config['ideName'] as String?;
    }
    return null;
  }

  /// Gets the connected IDE client from a list of MCP clients.
  Map<String, dynamic>? getConnectedIdeClient(
    List<Map<String, dynamic>>? mcpClients,
  ) {
    if (mcpClients == null) return null;
    try {
      return mcpClients.firstWhere(
        (client) =>
            client['type'] == 'connected' && client['name'] == 'ide',
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Host IP detection
  // ---------------------------------------------------------------------------

  /// Cache for host IP detection results.
  final Map<String, String> _hostIPCache = {};

  /// Detects the host IP to use to connect to the extension.
  Future<String> detectHostIP(bool isIdeRunningInWindows, int port) async {
    final cacheKey = '$isIdeRunningInWindows:$port';
    if (_hostIPCache.containsKey(cacheKey)) {
      return _hostIPCache[cacheKey]!;
    }

    final envOverride = Platform.environment['NEOMCLAW_IDE_HOST_OVERRIDE'];
    if (envOverride != null) {
      _hostIPCache[cacheKey] = envOverride;
      return envOverride;
    }

    // Default to localhost
    const defaultHost = '127.0.0.1';

    // WSL-specific host detection
    if (Platform.isLinux &&
        Platform.environment.containsKey('WSL_DISTRO_NAME') &&
        isIdeRunningInWindows) {
      try {
        final result = await Process.run('bash', [
          '-c',
          'ip route show | grep -i default',
        ]);
        if (result.exitCode == 0) {
          final match = RegExp(r'default via (\d+\.\d+\.\d+\.\d+)')
              .firstMatch(result.stdout as String);
          if (match != null) {
            final gatewayIP = match.group(1)!;
            if (await checkIdeConnection(gatewayIP, port)) {
              _hostIPCache[cacheKey] = gatewayIP;
              return gatewayIP;
            }
          }
        }
      } catch (_) {}
    }

    _hostIPCache[cacheKey] = defaultHost;
    return defaultHost;
  }

  // ---------------------------------------------------------------------------
  // IDE integration initialization
  // ---------------------------------------------------------------------------

  /// Initializes IDE detection and extension installation.
  Future<void> initializeIdeIntegration({
    required void Function(DetectedIDEInfo?) onIdeDetected,
    IdeType? ideToInstallExtension,
    required void Function() onShowIdeOnboarding,
    required void Function(IDEExtensionInstallationStatus?) onInstallationComplete,
  }) async {
    // Don't await so we don't block startup
    unawaited(findAvailableIDE().then(onIdeDetected));

    final ideType = ideToInstallExtension;
    if (ideType != null && isVSCodeIde(ideType)) {
      unawaited(
        isIDEExtensionInstalled(ideType).then((isAlreadyInstalled) {
          maybeInstallIDEExtension(ideType).then((status) {
            onInstallationComplete(status);
            if (status?.installed == true) {
              findAvailableIDE().then(onIdeDetected);
            }
          });
        }),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Terminal type helpers
  // ---------------------------------------------------------------------------

  /// Check if running in a supported VSCode terminal.
  bool isSupportedVSCodeTerminal() {
    final terminal = Platform.environment['TERM_PROGRAM'];
    if (terminal == null) return false;
    try {
      final ideType = IdeType.values.firstWhere((e) => e.name == terminal);
      return isVSCodeIde(ideType);
    } catch (_) {
      return false;
    }
  }

  /// Check if running in a supported JetBrains terminal.
  bool isSupportedJetBrainsTerminal() {
    final terminal = Platform.environment['TERMINAL_EMULATOR'];
    if (terminal == null) return false;
    try {
      final ideType = IdeType.values.firstWhere((e) => e.name == terminal);
      return isJetBrainsIde(ideType);
    } catch (_) {
      return false;
    }
  }

  /// Check if running in any supported IDE terminal.
  bool isSupportedTerminal() {
    return isSupportedVSCodeTerminal() ||
        isSupportedJetBrainsTerminal() ||
        Platform.environment['FORCE_CODE_TERMINAL'] == 'true';
  }

  /// Get the terminal IDE type if available.
  IdeType? getTerminalIdeType() {
    if (!isSupportedTerminal()) return null;
    final terminal = Platform.environment['TERM_PROGRAM'];
    try {
      return IdeType.values.firstWhere((e) => e.name == terminal);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onClose() {
    _currentSearchAbort?.complete();
    super.onClose();
  }
}
