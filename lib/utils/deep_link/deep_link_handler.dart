/// Deep Link Handler
///
/// Faithful port of neomage/src/utils/deepLink/*.ts
/// Covers: parseDeepLink.ts, terminalLauncher.ts, registerProtocol.ts,
///         protocolHandler.ts, banner.ts, terminalPreference.ts
///
/// Provides:
/// - neomage-cli:// URI parsing with security validation
/// - Terminal emulator detection and launch (macOS/Linux/Windows)
/// - OS protocol handler registration (.app bundle, .desktop, Windows registry)
/// - Deep link origin banner for security awareness
/// - Terminal preference capture for deep link handling
library;

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;
import 'package:sint/rx.dart';

import '../security/neomage_network_guard.dart';
import 'deep_link_parser.dart';
export 'deep_link_parser.dart';

bool _containsControlChars(String s) => containsDeepLinkControlChars(s);

// ═══════════════════════════════════════════════════════════════════════════
// TERMINAL LAUNCHER (terminalLauncher.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Terminal emulator information.
class TerminalInfo {
  final String name;
  final String command;

  const TerminalInfo({required this.name, required this.command});

  @override
  String toString() => 'TerminalInfo(name: $name, command: $command)';
}

/// macOS terminal entries in preference order.
class _MacosTerminal {
  final String name;
  final String bundleId;
  final String app;

  const _MacosTerminal({
    required this.name,
    required this.bundleId,
    required this.app,
  });
}

const List<_MacosTerminal> _macosTerminals = [
  _MacosTerminal(
    name: 'iTerm2',
    bundleId: 'com.googlecode.iterm2',
    app: 'iTerm',
  ),
  _MacosTerminal(
    name: 'Ghostty',
    bundleId: 'com.mitchellh.ghostty',
    app: 'Ghostty',
  ),
  _MacosTerminal(name: 'Kitty', bundleId: 'net.kovidgoyal.kitty', app: 'kitty'),
  _MacosTerminal(
    name: 'Alacritty',
    bundleId: 'org.alacritty',
    app: 'Alacritty',
  ),
  _MacosTerminal(
    name: 'WezTerm',
    bundleId: 'com.github.wez.wezterm',
    app: 'WezTerm',
  ),
  _MacosTerminal(
    name: 'Terminal.app',
    bundleId: 'com.apple.Terminal',
    app: 'Terminal',
  ),
];

/// Linux terminals in preference order.
const List<String> _linuxTerminals = [
  'ghostty',
  'kitty',
  'alacritty',
  'wezterm',
  'gnome-terminal',
  'konsole',
  'xfce4-terminal',
  'mate-terminal',
  'tilix',
  'xterm',
];

/// Detect the user's preferred terminal on macOS.
Future<TerminalInfo> _detectMacosTerminal({String? storedPreference}) async {
  // Check stored preference
  if (storedPreference != null) {
    final match = _macosTerminals
        .where((t) => t.app == storedPreference)
        .firstOrNull;
    if (match != null) {
      return TerminalInfo(name: match.name, command: match.app);
    }
  }

  // Check TERM_PROGRAM env var
  final termProgram = Platform.environment['TERM_PROGRAM'];
  if (termProgram != null) {
    final normalized = termProgram
        .replaceAll(RegExp(r'\.app$', caseSensitive: false), '')
        .toLowerCase();
    final match = _macosTerminals
        .where(
          (t) =>
              t.app.toLowerCase() == normalized ||
              t.name.toLowerCase() == normalized,
        )
        .firstOrNull;
    if (match != null) {
      return TerminalInfo(name: match.name, command: match.app);
    }
  }

  // Check installed via mdfind (Spotlight)
  for (final terminal in _macosTerminals) {
    try {
      final result = await Process.run(
        'mdfind',
        ['kMDItemCFBundleIdentifier == "${terminal.bundleId}"'],
        runInShell: false,
        environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty) {
        return TerminalInfo(name: terminal.name, command: terminal.app);
      }
    } catch (_) {}
  }

  // Fallback: check /Applications directly
  for (final terminal in _macosTerminals) {
    try {
      final exists = await Directory(
        '/Applications/${terminal.app}.app',
      ).exists();
      if (exists) {
        return TerminalInfo(name: terminal.name, command: terminal.app);
      }
    } catch (_) {}
  }

  // Terminal.app is always available
  return const TerminalInfo(name: 'Terminal.app', command: 'Terminal');
}

/// Detect the user's preferred terminal on Linux.
Future<TerminalInfo?> _detectLinuxTerminal() async {
  // Check $TERMINAL env var
  final termEnv = Platform.environment['TERMINAL'];
  if (termEnv != null) {
    final resolved = await _which(termEnv);
    if (resolved != null) {
      return TerminalInfo(name: p.basename(termEnv), command: resolved);
    }
  }

  // Check x-terminal-emulator (Debian/Ubuntu)
  final xte = await _which('x-terminal-emulator');
  if (xte != null) {
    return TerminalInfo(name: 'x-terminal-emulator', command: xte);
  }

  // Walk the priority list
  for (final terminal in _linuxTerminals) {
    final resolved = await _which(terminal);
    if (resolved != null) {
      return TerminalInfo(name: terminal, command: resolved);
    }
  }

  return null;
}

/// Detect the user's preferred terminal on Windows.
Future<TerminalInfo> _detectWindowsTerminal() async {
  final wt = await _which('wt.exe');
  if (wt != null) return TerminalInfo(name: 'Windows Terminal', command: wt);

  final pwsh = await _which('pwsh.exe');
  if (pwsh != null) return TerminalInfo(name: 'PowerShell', command: pwsh);

  final powershell = await _which('powershell.exe');
  if (powershell != null) {
    return TerminalInfo(name: 'PowerShell', command: powershell);
  }

  return const TerminalInfo(name: 'Command Prompt', command: 'cmd.exe');
}

/// Detect the user's preferred terminal emulator.
Future<TerminalInfo?> detectTerminal({String? storedPreference}) async {
  if (Platform.isMacOS) {
    return _detectMacosTerminal(storedPreference: storedPreference);
  } else if (Platform.isLinux) {
    return _detectLinuxTerminal();
  } else if (Platform.isWindows) {
    return _detectWindowsTerminal();
  }
  return null;
}

/// Launch Neomage in the detected terminal emulator.
Future<bool> launchInTerminal(
  String neomagePath,
  DeepLinkAction action, {
  String? storedPreference,
}) async {
  _validateExecutablePath(neomagePath);
  final terminal = await detectTerminal(storedPreference: storedPreference);
  if (terminal == null) {
    _logDebug('No terminal emulator detected');
    return false;
  }

  _logDebug('Launching in terminal: ${terminal.name} (${terminal.command})');
  final neomageArgs = ['--deep-link-origin'];
  if (action.repo != null) {
    neomageArgs.addAll(['--deep-link-repo', action.repo!]);
  }
  if (action.query != null) {
    neomageArgs.addAll(['--prefill', action.query!]);
  }

  if (Platform.isMacOS) {
    return _launchMacosTerminal(
      terminal,
      neomagePath,
      neomageArgs,
      action.cwd,
    );
  } else if (Platform.isLinux) {
    return _launchLinuxTerminal(
      terminal,
      neomagePath,
      neomageArgs,
      action.cwd,
    );
  } else if (Platform.isWindows) {
    return _launchWindowsTerminal(
      terminal,
      neomagePath,
      neomageArgs,
      action.cwd,
    );
  }
  return false;
}

/// Build parameterized `osascript` arguments using `on run argv` so zero
/// untrusted text is ever interpolated into AppleScript source code.
List<String> buildMacOsTerminalAppleScriptArgs(
  String terminalApp,
  String shellCommand,
) {
  if (terminalApp == 'iTerm') {
    const script = '''on run argv
  set shCmd to item 1 of argv
  tell application "iTerm"
    if running then
      create window with default profile
    else
      activate
    end if
    tell current session of current window
      write text shCmd
    end tell
  end tell
end run''';
    return <String>['-e', script, '--', shellCommand];
  }
  if (terminalApp == 'Terminal') {
    const script = '''on run argv
  set shCmd to item 1 of argv
  tell application "Terminal"
    do script shCmd
    activate
  end tell
end run''';
    return <String>['-e', script, '--', shellCommand];
  }
  throw ArgumentError.value(terminalApp, 'terminalApp', 'Unsupported AppleScript terminal');
}

/// Launch in a macOS terminal.
Future<bool> _launchMacosTerminal(
  TerminalInfo terminal,
  String neomagePath,
  List<String> neomageArgs,
  String? cwd,
) async {
  Future<ProcessResult> runSafe(String exe, List<String> args) {
    return Process.run(
      exe,
      args,
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
      includeParentEnvironment: false,
    ).timeout(const Duration(seconds: 10));
  }

  switch (terminal.command) {
    // PARAMETERIZED ARGV APPLESCRIPT PATHS (zero AppleScript interpolation)
    case 'iTerm':
      final shCmd = _buildShellCommand(neomagePath, neomageArgs, cwd);
      final result = await runSafe(
        'osascript',
        buildMacOsTerminalAppleScriptArgs('iTerm', shCmd),
      );
      if (result.exitCode == 0) return true;
      break;

    case 'Terminal':
      final shCmd = _buildShellCommand(neomagePath, neomageArgs, cwd);
      final result = await runSafe(
        'osascript',
        buildMacOsTerminalAppleScriptArgs('Terminal', shCmd),
      );
      return result.exitCode == 0;

    // PURE ARGV PATHS (no shell)
    case 'Ghostty':
      final args = [
        '-na',
        terminal.command,
        '--args',
        '--window-save-state=never',
      ];
      if (cwd != null) args.add('--working-directory=$cwd');
      args.addAll(['-e', neomagePath, ...neomageArgs]);
      final result = await runSafe('open', args);
      if (result.exitCode == 0) return true;
      break;

    case 'Alacritty':
      final args = ['-na', terminal.command, '--args'];
      if (cwd != null) args.addAll(['--working-directory', cwd]);
      args.addAll(['-e', neomagePath, ...neomageArgs]);
      final result = await runSafe('open', args);
      if (result.exitCode == 0) return true;
      break;

    case 'kitty':
      final args = ['-na', terminal.command, '--args'];
      if (cwd != null) args.addAll(['--directory', cwd]);
      args.addAll([neomagePath, ...neomageArgs]);
      final result = await runSafe('open', args);
      if (result.exitCode == 0) return true;
      break;

    case 'WezTerm':
      final args = ['-na', terminal.command, '--args', 'start'];
      if (cwd != null) args.addAll(['--cwd', cwd]);
      args.addAll(['--', neomagePath, ...neomageArgs]);
      final result = await runSafe('open', args);
      if (result.exitCode == 0) return true;
      break;
  }

  // Fallback to Terminal.app
  if (terminal.command != 'Terminal') {
    _logDebug(
      'Failed to launch ${terminal.name}, falling back to Terminal.app',
    );
    return _launchMacosTerminal(
      const TerminalInfo(name: 'Terminal.app', command: 'Terminal'),
      neomagePath,
      neomageArgs,
      cwd,
    );
  }
  return false;
}

/// Launch in a Linux terminal (all pure argv).
Future<bool> _launchLinuxTerminal(
  TerminalInfo terminal,
  String neomagePath,
  List<String> neomageArgs,
  String? cwd,
) async {
  List<String> args;
  String? spawnCwd;

  switch (terminal.name) {
    case 'gnome-terminal':
      args = cwd != null ? ['--working-directory=$cwd', '--'] : ['--'];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    case 'konsole':
      args = cwd != null ? ['--workdir', cwd, '-e'] : ['-e'];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    case 'kitty':
      args = cwd != null ? ['--directory', cwd] : [];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    case 'wezterm':
      args = cwd != null ? ['start', '--cwd', cwd, '--'] : ['start', '--'];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    case 'alacritty':
      args = cwd != null ? ['--working-directory', cwd, '-e'] : ['-e'];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    case 'ghostty':
      args = cwd != null ? ['--working-directory=$cwd', '-e'] : ['-e'];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    case 'xfce4-terminal':
    case 'mate-terminal':
      args = cwd != null ? ['--working-directory=$cwd', '-x'] : ['-x'];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    case 'tilix':
      args = cwd != null ? ['--working-directory=$cwd', '-e'] : ['-e'];
      args.addAll([neomagePath, ...neomageArgs]);
      break;
    default:
      args = ['-e', neomagePath, ...neomageArgs];
      spawnCwd = cwd;
      break;
  }

  return _spawnDetached(terminal.command, args, cwd: spawnCwd);
}

/// Launch in a Windows terminal.
Future<bool> _launchWindowsTerminal(
  TerminalInfo terminal,
  String neomagePath,
  List<String> neomageArgs,
  String? cwd,
) async {
  final args = <String>[];

  switch (terminal.name) {
    case 'Windows Terminal':
      if (cwd != null) args.addAll(['-d', cwd]);
      args.addAll(['--', neomagePath, ...neomageArgs]);
      break;
    case 'PowerShell':
      final cdCmd = cwd != null ? 'Set-Location ${_psQuote(cwd)}; ' : '';
      args.addAll([
        '-NoExit',
        '-Command',
        '$cdCmd& ${_psQuote(neomagePath)} ${neomageArgs.map(_psQuote).join(' ')}',
      ]);
      break;
    default:
      final cdCmd = cwd != null ? 'cd /d ${_cmdQuote(cwd)} && ' : '';
      args.addAll([
        '/k',
        '$cdCmd${_cmdQuote(neomagePath)} ${neomageArgs.map(_cmdQuote).join(' ')}',
      ]);
      break;
  }

  return _spawnDetached(terminal.command, args);
}

/// Spawn a terminal detached so the handler process can exit.
Future<bool> _spawnDetached(
  String command,
  List<String> args, {
  String? cwd,
}) async {
  if (cwd != null &&
      (cwd.startsWith('//') ||
          cwd.startsWith(r'\\') ||
          _containsControlChars(cwd))) {
    return false;
  }
  try {
    await Process.start(
      command,
      args,
      mode: ProcessStartMode.detached,
      workingDirectory: cwd,
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
      includeParentEnvironment: false,
    );
    // Detached process — no need to wait
    return true;
  } catch (e) {
    _logDebug('Failed to spawn $command: $e');
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHELL QUOTING UTILITIES
// ═══════════════════════════════════════════════════════════════════════════

/// Build a single-quoted POSIX shell command string.
/// Only used by AppleScript paths (iTerm, Terminal.app).
String _buildShellCommand(
  String neomagePath,
  List<String> neomageArgs,
  String? cwd,
) {
  final cdPrefix = cwd != null ? 'cd -- ${_shellQuote(cwd)} && ' : '';
  return '$cdPrefix${[neomagePath, ...neomageArgs].map(_shellQuote).join(' ')}';
}

/// POSIX single-quote escaping.
String _shellQuote(String s) {
  return "'${s.replaceAll("'", "'\\''")}'";
}

/// PowerShell single-quoted string. '' for literal single quote.
String _psQuote(String s) {
  return "'${s.replaceAll("'", "''")}'";
}

/// cmd.exe argument quoting. Strip " (cannot be safely represented),
/// escape % as %%, double trailing backslashes.
String _cmdQuote(String arg) {
  final stripped = arg.replaceAll('"', '').replaceAll('%', '%%');
  final escaped = stripped.replaceAllMapped(
    RegExp(r'(\\+)$'),
    (m) => '${m.group(1)}${m.group(1)}',
  );
  return '"$escaped"';
}

// ═══════════════════════════════════════════════════════════════════════════
// PROTOCOL REGISTRATION (registerProtocol.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// macOS .app bundle directory path.
String get _macosAppDir => p.join(_homeDir(), 'Applications', macosAppName);

/// macOS symlink path inside the .app bundle.
String get _macosSymlinkPath =>
    p.join(_macosAppDir, 'Contents', 'MacOS', 'neomage');

/// Linux .desktop file path.
String _linuxDesktopPath() {
  final xdgDataHome =
      Platform.environment['XDG_DATA_HOME'] ??
      p.join(_homeDir(), '.local', 'share');
  return p.join(xdgDataHome, 'applications', desktopFileName);
}

/// Windows registry key.
const String _windowsRegKey =
    'HKEY_CURRENT_USER\\Software\\Classes\\$deepLinkProtocol';
const String _windowsCommandKey = '$_windowsRegKey\\shell\\open\\command';

/// Linux .desktop Exec line.
String _linuxExecLine(String neomagePath) =>
    'Exec="$neomagePath" --handle-uri %u';

/// Windows command value.
String _windowsCommandValue(String neomagePath) =>
    '"$neomagePath" --handle-uri "%1"';

/// Register the protocol handler on macOS.
/// Creates a .app bundle with a symlink to the neomage binary.
Future<void> _registerMacos(String neomagePath) async {
  final contentsDir = p.join(_macosAppDir, 'Contents');

  // Remove existing
  try {
    await Directory(_macosAppDir).delete(recursive: true);
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode != 2 /* ENOENT */ ) rethrow;
  }

  await Directory(p.dirname(_macosSymlinkPath)).create(recursive: true);

  // Info.plist
  final infoPlist =
      '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$macosBundleId</string>
  <key>CFBundleName</key>
  <string>$appName</string>
  <key>CFBundleExecutable</key>
  <string>neomage</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSBackgroundOnly</key>
  <true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>Neomage Deep Link</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>$deepLinkProtocol</string>
      </array>
    </dict>
  </array>
</dict>
</plist>''';

  await File(p.join(contentsDir, 'Info.plist')).writeAsString(infoPlist);

  // Symlink to the signed neomage binary
  await Link(_macosSymlinkPath).create(neomagePath);

  // Re-register with LaunchServices
  const lsregister =
      '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';
  await Process.run(
    lsregister,
    ['-R', _macosAppDir],
    runInShell: false,
    environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
    includeParentEnvironment: false,
  ).timeout(const Duration(seconds: 15));

  _logDebug(
    'Registered $deepLinkProtocol:// protocol handler at $_macosAppDir',
  );
}

/// Register the protocol handler on Linux.
Future<void> _registerLinux(String neomagePath) async {
  final desktopPath = _linuxDesktopPath();
  await Directory(p.dirname(desktopPath)).create(recursive: true);

  final desktopEntry =
      '''[Desktop Entry]
Name=$appName
Comment=Handle $deepLinkProtocol:// deep links for Neomage
${_linuxExecLine(neomagePath)}
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/$deepLinkProtocol;
''';

  await File(desktopPath).writeAsString(desktopEntry);

  // Register with xdg-mime if available
  final xdgMime = await _which('xdg-mime');
  if (xdgMime != null) {
    final result = await Process.run(
      xdgMime,
      [
        'default',
        desktopFileName,
        'x-scheme-handler/$deepLinkProtocol',
      ],
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
      includeParentEnvironment: false,
    ).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) {
      throw Exception('xdg-mime exited with code ${result.exitCode}');
    }
  }

  _logDebug('Registered $deepLinkProtocol:// protocol handler at $desktopPath');
}

/// Register the protocol handler on Windows via the registry.
Future<void> _registerWindows(String neomagePath) async {
  final regCommands = [
    ['add', _windowsRegKey, '/ve', '/d', 'URL:$appName', '/f'],
    ['add', _windowsRegKey, '/v', 'URL Protocol', '/d', '', '/f'],
    [
      'add',
      _windowsCommandKey,
      '/ve',
      '/d',
      _windowsCommandValue(neomagePath),
      '/f',
    ],
  ];

  for (final args in regCommands) {
    final result = await Process.run(
      'reg',
      args,
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
      includeParentEnvironment: false,
    ).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) {
      throw Exception('reg add exited with code ${result.exitCode}');
    }
  }

  _logDebug(
    'Registered $deepLinkProtocol:// protocol handler in Windows registry',
  );
}

/// Validate that an executable path is safe for OS protocol registration and argv launch.
void _validateExecutablePath(String neomagePath) {
  if (neomagePath.trim().isEmpty ||
      _containsControlChars(neomagePath) ||
      neomagePath.contains('"') ||
      neomagePath.contains('<') ||
      neomagePath.contains('>') ||
      neomagePath.contains('&') ||
      neomagePath.split(RegExp(r'[/\\]')).contains('..')) {
    throw ArgumentError.value(
      neomagePath,
      'neomagePath',
      'Executable path contains unsafe characters or traversal segments',
    );
  }
}

/// Register the neomage-cli:// protocol handler with the operating system.
Future<void> registerProtocolHandler([String? neomagePath]) async {
  final resolved = neomagePath ?? await _resolveNeomagePath();
  _validateExecutablePath(resolved);

  if (Platform.isMacOS) {
    await _registerMacos(resolved);
  } else if (Platform.isLinux) {
    await _registerLinux(resolved);
  } else if (Platform.isWindows) {
    await _registerWindows(resolved);
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

/// Resolve the neomage binary path for protocol registration.
Future<String> _resolveNeomagePath() async {
  final binaryName = Platform.isWindows ? 'neomage.exe' : 'neomage';
  final userBinDir = Platform.isWindows
      ? p.join(
          Platform.environment['LOCALAPPDATA'] ?? '',
          'Programs',
          'neomage',
        )
      : p.join(_homeDir(), '.local', 'bin');
  final stablePath = p.join(userBinDir, binaryName);
  try {
    await File(stablePath).resolveSymbolicLinks();
    return stablePath;
  } catch (_) {
    return Platform.resolvedExecutable;
  }
}

/// Check whether the OS-level protocol handler is current.
Future<bool> isProtocolHandlerCurrent(String neomagePath) async {
  try {
    if (Platform.isMacOS) {
      final target = await Link(_macosSymlinkPath).target();
      return target == neomagePath;
    } else if (Platform.isLinux) {
      final content = await File(_linuxDesktopPath()).readAsString();
      return content.contains(_linuxExecLine(neomagePath));
    } else if (Platform.isWindows) {
      final result = await Process.run(
        'reg',
        [
          'query',
          _windowsCommandKey,
          '/ve',
        ],
        runInShell: false,
        environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 10));
      return result.exitCode == 0 &&
          (result.stdout as String).contains(
            _windowsCommandValue(neomagePath),
          );
    }
  } catch (_) {}
  return false;
}

/// Auto-register the protocol handler when missing or stale.
Future<void> ensureDeepLinkProtocolRegistered() async {
  final neomagePath = await _resolveNeomagePath();
  if (await isProtocolHandlerCurrent(neomagePath)) return;

  // Check failure backoff
  final configHome =
      Platform.environment['MAGE_CONFIG_HOME'] ??
      p.join(_homeDir(), '.neomage');
  final failureMarkerPath = p.join(configHome, '.deep-link-register-failed');
  try {
    final stat = await File(failureMarkerPath).stat();
    if (DateTime.now().millisecondsSinceEpoch -
            stat.modified.millisecondsSinceEpoch <
        failureBackoffMs) {
      return;
    }
  } catch (_) {
    // Marker absent — proceed
  }

  try {
    await registerProtocolHandler(neomagePath);
    _logDebug(
      'Auto-registered $deepLinkProtocol:// deep link protocol handler',
    );
    try {
      await File(failureMarkerPath).delete();
    } catch (_) {}
  } catch (e) {
    _logDebug('Failed to auto-register deep link protocol handler: $e');
    try {
      await File(failureMarkerPath).writeAsString('');
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PROTOCOL HANDLER (protocolHandler.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Handle an incoming deep link URI.
/// Called from the CLI entry point when `--handle-uri` is passed.
Future<int> handleDeepLinkUri(String uri) async {
  _logDebug('Handling deep link URI: $uri');

  DeepLinkAction action;
  try {
    action = parseDeepLink(uri);
  } catch (e) {
    stderr.writeln('Deep link error: $e');
    return 1;
  }

  _logDebug('Parsed deep link action: $action');

  // Resolve working directory
  final cwd = action.cwd ?? _homeDir();

  // Warm FETCH_HEAD check for repo links
  if (action.repo != null) {
    await readLastFetchTime(cwd);
  }

  final launched = await launchInTerminal(
    Platform.resolvedExecutable,
    DeepLinkAction(query: action.query, cwd: cwd, repo: action.repo),
  );

  if (!launched) {
    stderr.writeln(
      'Failed to open a terminal. Make sure a supported terminal emulator is installed.',
    );
    return 1;
  }

  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// BANNER (banner.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Info needed to build the deep link origin banner.
class DeepLinkBannerInfo {
  final String cwd;
  final int? prefillLength;
  final String? repo;
  final DateTime? lastFetch;

  const DeepLinkBannerInfo({
    required this.cwd,
    this.prefillLength,
    this.repo,
    this.lastFetch,
  });
}

/// Build the warning banner for a deep-link-originated session.
String buildDeepLinkBanner(DeepLinkBannerInfo info) {
  final lines = <String>[
    'This session was opened by an external deep link in ${_tildify(info.cwd)}',
  ];

  if (info.repo != null) {
    final age = info.lastFetch != null
        ? _formatRelativeTimeAgo(info.lastFetch!)
        : 'never';
    final stale =
        info.lastFetch == null ||
        DateTime.now().millisecondsSinceEpoch -
                info.lastFetch!.millisecondsSinceEpoch >
            staleFetchWarnMs;
    lines.add(
      'Resolved ${info.repo} from local clones - last fetched $age${stale ? ' -- NEOMAGE.md may be stale' : ''}',
    );
  }

  if (info.prefillLength != null && info.prefillLength! > 0) {
    if (info.prefillLength! > longPrefillThreshold) {
      lines.add(
        'The prompt below (${info.prefillLength} chars) was supplied by the link -- scroll to review the entire prompt before pressing Enter.',
      );
    } else {
      lines.add(
        'The prompt below was supplied by the link -- review carefully before pressing Enter.',
      );
    }
  }

  return lines.join('\n');
}

/// Read the mtime of .git/FETCH_HEAD.
Future<DateTime?> readLastFetchTime(String cwd) async {
  try {
    // Find .git directory
    final gitDir = await _findGitDir(cwd);
    if (gitDir == null) return null;

    final fetchHeadPath = p.join(gitDir, 'FETCH_HEAD');
    try {
      final stat = await File(fetchHeadPath).stat();
      return stat.modified;
    } catch (_) {
      return null;
    }
  } catch (_) {
    return null;
  }
}

/// Find the .git directory for a working directory.
Future<String?> _findGitDir(String cwd) async {
  if (cwd.startsWith('//') ||
      cwd.startsWith(r'\\') ||
      _containsControlChars(cwd)) {
    return null;
  }
  try {
    final result = await Process.run(
      'git',
      ['rev-parse', '--git-dir'],
      workingDirectory: cwd,
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
      includeParentEnvironment: false,
    ).timeout(const Duration(seconds: 5));
    if (result.exitCode == 0) {
      final gitDir = (result.stdout as String).trim();
      return p.isAbsolute(gitDir) ? gitDir : p.join(cwd, gitDir);
    }
  } catch (_) {}
  return null;
}

/// Shorten home-dir-prefixed paths to ~ notation.
String _tildify(String path) {
  final home = _homeDir();
  if (path == home) return '~';
  if (path.startsWith('$home${p.separator}')) {
    return '~${path.substring(home.length)}';
  }
  return path;
}

/// Format a relative time ago string.
String _formatRelativeTimeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
  if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}

// ═══════════════════════════════════════════════════════════════════════════
// TERMINAL PREFERENCE (terminalPreference.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Map TERM_PROGRAM env var values (lowercased) to the app name used by
/// launchMacosTerminal's switch cases.
const Map<String, String> _termProgramToApp = {
  'iterm': 'iTerm',
  'iterm.app': 'iTerm',
  'ghostty': 'Ghostty',
  'kitty': 'kitty',
  'alacritty': 'Alacritty',
  'wezterm': 'WezTerm',
  'apple_terminal': 'Terminal',
};

/// Capture the current terminal from TERM_PROGRAM and return the app name.
/// Returns null if not on macOS or TERM_PROGRAM not recognized.
String? captureTerminalPreference() {
  if (!Platform.isMacOS) return null;

  final termProgram = Platform.environment['TERM_PROGRAM'];
  if (termProgram == null) return null;

  return _termProgramToApp[termProgram.toLowerCase()];
}

// ═══════════════════════════════════════════════════════════════════════════
// DEEP LINK CONTROLLER (Sint pattern)
// ═══════════════════════════════════════════════════════════════════════════

/// Sint controller managing deep link state and operations.
class DeepLinkController extends SintController {
  /// Whether the current session was opened by a deep link.
  final isDeepLinkSession = false.obs;

  /// The parsed deep link action (if any).
  final currentAction = Rxn<DeepLinkAction>();

  /// Banner text for the current session.
  final bannerText = ''.obs;

  /// Whether the protocol handler is registered.
  final isProtocolRegistered = false.obs;

  /// Stored terminal preference.
  final terminalPreference = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    // Capture terminal preference on init
    terminalPreference.value = captureTerminalPreference();
  }

  /// Handle an incoming deep link URI.
  Future<int> handleUri(String uri) async {
    return handleDeepLinkUri(uri);
  }

  /// Parse a deep link and set session state.
  void setDeepLinkSession(DeepLinkAction action, String cwd) {
    isDeepLinkSession.value = true;
    currentAction.value = action;
    bannerText.value = buildDeepLinkBanner(
      DeepLinkBannerInfo(
        cwd: cwd,
        prefillLength: action.query?.length,
        repo: action.repo,
      ),
    );
  }

  /// Register the protocol handler.
  Future<void> registerProtocol([String? neomagePath]) async {
    await registerProtocolHandler(neomagePath);
    isProtocolRegistered.value = true;
  }

  /// Check and auto-register if needed.
  Future<void> ensureRegistered() async {
    await ensureDeepLinkProtocolRegistered();
    final neomagePath = await _resolveNeomagePath();
    isProtocolRegistered.value = await isProtocolHandlerCurrent(neomagePath);
  }

  /// Build a deep link URL.
  String buildLink({String? query, String? cwd, String? repo}) {
    return buildDeepLink(DeepLinkAction(query: query, cwd: cwd, repo: repo));
  }

  /// Parse a deep link URL.
  DeepLinkAction parseLink(String uri) {
    return parseDeepLink(uri);
  }

  /// Detect the user's terminal.
  Future<TerminalInfo?> getDetectedTerminal() async {
    return detectTerminal(storedPreference: terminalPreference.value);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

String _homeDir() =>
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    '/tmp';

final RegExp _safeCommandTokenRegex = RegExp(r'^[A-Za-z0-9._+/\\:-]{1,256}$');

/// Resolve a command to its full path using `which` / `where`.
Future<String?> _which(String command) async {
  if (command.isEmpty ||
      command.startsWith('-') ||
      command.startsWith('//') ||
      command.startsWith(r'\\') ||
      _containsControlChars(command) ||
      !_safeCommandTokenRegex.hasMatch(command)) {
    return null;
  }
  try {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(
      cmd,
      [command],
      runInShell: false,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(),
      includeParentEnvironment: false,
    ).timeout(const Duration(seconds: 5));
    if (result.exitCode == 0) {
      final resolved = (result.stdout as String).trim().split('\n').first.trim();
      return resolved.isNotEmpty ? resolved : null;
    }
  } catch (_) {}
  return null;
}

void _logDebug(String message) {
  assert(() {
    // ignore: avoid_print
    print('[DeepLink] $message');
    return true;
  }());
}
