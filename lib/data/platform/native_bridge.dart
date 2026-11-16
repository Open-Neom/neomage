// Native bridge — port of neomage/src/native-ts/.
// Platform-specific native bindings: file dialogs, clipboard, notifications,
// hotkeys, and system info.  Provides a concrete DesktopNativeBridge for
// macOS/Linux/Windows and a stub WebNativeBridge.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

// ── Enums ──────────────────────────────────────────────────────────────────

/// Target native platform.
enum NativePlatform { macos, linux, windows, android, ios, web }

// ── Data classes ───────────────────────────────────────────────────────────

/// What the current platform supports at the native level.
class NativeCapabilities {
  final bool clipboard;
  final bool notifications;
  final bool fileDialog;
  final bool tray;
  final bool globalHotkeys;
  final bool biometrics;

  const NativeCapabilities({
    this.clipboard = false,
    this.notifications = false,
    this.fileDialog = false,
    this.tray = false,
    this.globalHotkeys = false,
    this.biometrics = false,
  });
}

/// System information snapshot.
class SystemInfo {
  final String os;
  final String version;
  final String arch;
  final String hostname;
  final int cpuCores;

  /// Total physical memory in bytes.
  final int memoryBytes;

  /// Default shell (e.g. /bin/zsh, cmd.exe).
  final String shell;

  const SystemInfo({
    required this.os,
    required this.version,
    required this.arch,
    required this.hostname,
    required this.cpuCores,
    required this.memoryBytes,
    required this.shell,
  });

  @override
  String toString() =>
      'SystemInfo(os=$os, version=$version, arch=$arch, '
      'hostname=$hostname, cpuCores=$cpuCores, '
      'memory=${(memoryBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB, '
      'shell=$shell)';
}

// ── Abstract bridge ────────────────────────────────────────────────────────

/// Platform-agnostic interface to native OS capabilities.
abstract class NativeBridge {
  /// Detect the current platform.
  NativePlatform getPlatform();

  /// What this platform supports.
  NativeCapabilities getCapabilities();

  /// Gather system information.
  Future<SystemInfo> getSystemInfo();

  // ── File dialogs ──────────────────────────────────────────────────────

  /// Show an open-file dialog.  Returns selected paths or `null` if
  /// cancelled.
  Future<List<String>?> showFileDialog({
    String? title,
    List<String>? filters,
    bool multiple = false,
    bool directory = false,
  });

  /// Show a save-file dialog.  Returns the chosen path or `null`.
  Future<String?> showSaveDialog({
    String? title,
    String? defaultName,
    List<String>? filters,
  });

  // ── Clipboard ─────────────────────────────────────────────────────────

  /// Write [text] to the system clipboard.
  Future<void> setClipboard(String text);

  /// Read the current clipboard text, or `null` if unavailable.
  Future<String?> getClipboard();

  // ── Notifications ─────────────────────────────────────────────────────

  /// Show a native OS notification.
  Future<void> showNativeNotification(
    String title,
    String body, {
    String? icon,
    bool sound = false,
  });

  // ── Open / reveal ─────────────────────────────────────────────────────

  /// Open [url] in the default browser.
  Future<void> openUrl(String url);

  /// Open [path] in the system editor, optionally jumping to [line] and
  /// [column].
  Future<void> openInEditor(String path, {int? line, int? column});

  /// Reveal [path] in the platform file manager.
  Future<void> revealInFinder(String path);

  // ── Environment ───────────────────────────────────────────────────────

  /// Read an environment variable.
  String? getEnvironmentVariable(String name);

  // ── Process ───────────────────────────────────────────────────────────

  /// Launch a detached process (fire-and-forget).
  Future<void> executeDetached(String command, List<String> args);

  // ── Global hotkeys ────────────────────────────────────────────────────

  /// Register a global hotkey.
  void registerGlobalHotkey(
    String key,
    List<String> modifiers,
    void Function() callback,
  );

  /// Unregister a previously registered global hotkey.
  void unregisterGlobalHotkey(String key);
}

// ── Desktop implementation ─────────────────────────────────────────────────

/// Concrete bridge for macOS, Linux, and Windows using [Process.run].
class DesktopNativeBridge implements NativeBridge {
  final NativePlatform _platform;
  final Map<String, void Function()> _hotkeys = {};

  DesktopNativeBridge() : _platform = _detectPlatform();

  @override
  NativePlatform getPlatform() => _platform;

  @override
  NativeCapabilities getCapabilities() => NativeCapabilities(
    clipboard: true,
    notifications: true,
    fileDialog:
        _platform == NativePlatform.macos || _platform == NativePlatform.linux,
    tray: _platform == NativePlatform.macos,
    globalHotkeys: false, // Requires native plugin — stubbed.
    biometrics: _platform == NativePlatform.macos,
  );

  // ── System info ───────────────────────────────────────────────────────

  @override
  Future<SystemInfo> getSystemInfo() async {
    final os = Platform.operatingSystem;
    final version = Platform.operatingSystemVersion;
    final hostname = Platform.localHostname;

    final arch = await _runSimple('uname', ['-m']);
    final cpuCores = Platform.numberOfProcessors;

    int memoryBytes = 0;
    if (_platform == NativePlatform.macos) {
      final raw = await _runSimple('sysctl', ['-n', 'hw.memsize']);
      memoryBytes = int.tryParse(raw.trim()) ?? 0;
    } else if (_platform == NativePlatform.linux) {
      final raw = await _runSimple('grep', ['MemTotal', '/proc/meminfo']);
      final match = RegExp(r'(\d+)').firstMatch(raw);
      memoryBytes = (int.tryParse(match?.group(1) ?? '0') ?? 0) * 1024;
    }

    final shell =
        Platform.environment['SHELL'] ??
        Platform.environment['COMSPEC'] ??
        '/bin/sh';

    return SystemInfo(
      os: os,
      version: version,
      arch: arch.trim(),
      hostname: hostname,
      cpuCores: cpuCores,
      memoryBytes: memoryBytes,
      shell: shell,
    );
  }

  // ── File dialogs ──────────────────────────────────────────────────────

  @override
  Future<List<String>?> showFileDialog({
    String? title,
    List<String>? filters,
    bool multiple = false,
    bool directory = false,
  }) async {
    if (_platform == NativePlatform.macos) {
      return _macosFileDialog(
        title: title,
        filters: filters,
        multiple: multiple,
        directory: directory,
      );
    }
    if (_platform == NativePlatform.linux) {
      return _zenityFileDialog(
        title: title,
        filters: filters,
        multiple: multiple,
        directory: directory,
      );
    }
    // Windows / other — not yet implemented.
    return null;
  }

  static final RegExp _safeFilterToken = RegExp(r'^[A-Za-z0-9._-]{1,32}$');
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

  /// Strictly validates external browser URLs (`https://`, `http://`, `mailto:`),
  /// blocking `file://`, `javascript:`, `smb://`, UNC paths, and CLI options (`-a`).
  static bool isAllowedBrowserUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty || trimmed.length > 4096) return false;
    if (trimmed.startsWith('-') ||
        trimmed.startsWith('//') ||
        trimmed.startsWith(r'\\')) {
      return false;
    }
    if (_controlChars.hasMatch(trimmed)) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https' || scheme == 'http') {
      return uri.host.isNotEmpty;
    }
    if (scheme == 'mailto') {
      return uri.path.isNotEmpty && !uri.path.startsWith('-');
    }
    return false;
  }

  /// Parameterizes macOS `choose file name` via `on run argv` (zero string interpolation).
  static List<String> buildMacOsSaveDialogArgs({
    String? title,
    String? defaultName,
  }) {
    final cleanTitle = (title ?? '').replaceAll('\x00', '').trim();
    final cleanDefault = (defaultName ?? '')
        .replaceAll(RegExp(r'[\x00/\\:]'), '')
        .trim();
    const script = '''
on run argv
  set hasPrompt to (item 1 of argv) is "1"
  set promptText to item 2 of argv
  set hasDefault to (item 3 of argv) is "1"
  set defaultText to item 4 of argv
  if hasPrompt and hasDefault then
    return POSIX path of (choose file name with prompt promptText default name defaultText)
  else if hasPrompt then
    return POSIX path of (choose file name with prompt promptText)
  else if hasDefault then
    return POSIX path of (choose file name default name defaultText)
  else
    return POSIX path of (choose file name)
  end if
end run''';
    return <String>[
      '-e',
      script,
      '--',
      cleanTitle.isNotEmpty ? '1' : '0',
      cleanTitle,
      cleanDefault.isNotEmpty ? '1' : '0',
      cleanDefault,
    ];
  }

  /// Parameterizes macOS `display notification` via `on run argv` (zero string interpolation).
  static List<String> buildMacOsNotificationArgs(
    String title,
    String body, {
    bool sound = false,
  }) {
    final cleanTitle = title.replaceAll('\x00', '').trim();
    final cleanBody = body.replaceAll('\x00', '').trim();
    final cappedTitle = cleanTitle.length > 256
        ? cleanTitle.substring(0, 256)
        : cleanTitle;
    final cappedBody = cleanBody.length > 2048
        ? cleanBody.substring(0, 2048)
        : cleanBody;
    const script = '''
on run argv
  set bodyText to item 1 of argv
  set titleText to item 2 of argv
  set playSound to (item 3 of argv) is "1"
  if playSound then
    display notification bodyText with title titleText sound name "default"
  else
    display notification bodyText with title titleText
  end if
end run''';
    return <String>[
      '-e',
      script,
      '--',
      cappedBody,
      cappedTitle,
      sound ? '1' : '0',
    ];
  }

  /// Parameterizes macOS `choose file` / `choose folder` via `on run argv` and
  /// strictly validates file-type filter tokens against `^[A-Za-z0-9._-]{1,32}$`.
  static List<String> buildMacOsFileDialogArgs({
    String? title,
    List<String>? filters,
    bool multiple = false,
    bool directory = false,
  }) {
    final cleanTitle = (title ?? '').replaceAll('\x00', '').trim();
    final safeFilters = (filters ?? const <String>[])
        .map((f) => f.trim())
        .where(_safeFilterToken.hasMatch)
        .take(32)
        .toList();

    final typeClause = (!directory && safeFilters.isNotEmpty)
        ? ' of type {${safeFilters.map((f) => '"$f"').join(', ')}}'
        : '';
    final multiClause = (!directory && multiple)
        ? ' with multiple selections allowed'
        : '';
    final targetCmd = directory ? 'choose folder' : 'choose file';
    final script = '''
on run argv
  set hasPrompt to (item 1 of argv) is "1"
  set promptText to item 2 of argv
  if hasPrompt then
    return $targetCmd with prompt promptText$multiClause$typeClause
  else
    return $targetCmd$multiClause$typeClause
  end if
end run''';
    return <String>[
      '-e',
      script,
      '--',
      cleanTitle.isNotEmpty ? '1' : '0',
      cleanTitle,
    ];
  }

  static bool _isSafeLocalPathArg(String path) {
    if (path.isEmpty || path.length > 4096) return false;
    if (path.contains('\x00') || path.startsWith('-')) return false;
    if (path.startsWith('//') || path.startsWith(r'\\')) return false;
    return true;
  }

  @override
  Future<String?> showSaveDialog({
    String? title,
    String? defaultName,
    List<String>? filters,
  }) async {
    if (_platform == NativePlatform.macos) {
      final result = await _runSimple(
        'osascript',
        buildMacOsSaveDialogArgs(title: title, defaultName: defaultName),
        timeout: const Duration(seconds: 120),
      );
      return result.trim().isEmpty ? null : result.trim();
    }
    return null;
  }

  // ── Clipboard ─────────────────────────────────────────────────────────

  @override
  Future<void> setClipboard(String text) async {
    if (text.length > 4 * 1024 * 1024) {
      throw ArgumentError('Clipboard payload exceeds 4 MiB limit');
    }
    if (_platform == NativePlatform.macos) {
      await _runPiped('pbcopy', text);
    } else if (_platform == NativePlatform.linux) {
      await _runPiped('xclip', text, args: ['-selection', 'clipboard']);
    } else if (_platform == NativePlatform.windows) {
      await _runPiped('clip', text);
    }
  }

  @override
  Future<String?> getClipboard() async {
    if (_platform == NativePlatform.macos) {
      return (await _runSimple('pbpaste', [])).trimRight();
    }
    if (_platform == NativePlatform.linux) {
      return (await _runSimple('xclip', [
        '-selection',
        'clipboard',
        '-o',
      ])).trimRight();
    }
    return null;
  }

  // ── Notifications ─────────────────────────────────────────────────────

  @override
  Future<void> showNativeNotification(
    String title,
    String body, {
    String? icon,
    bool sound = false,
  }) async {
    if (_platform == NativePlatform.macos) {
      await _runSimple(
        'osascript',
        buildMacOsNotificationArgs(title, body, sound: sound),
      );
    } else if (_platform == NativePlatform.linux) {
      final cleanTitle = title.replaceAll('\x00', '').trim();
      final cleanBody = body.replaceAll('\x00', '').trim();
      final args = <String>[];
      if (icon != null && _isSafeLocalPathArg(icon)) {
        args.addAll(['-i', icon]);
      }
      args.addAll(['--', cleanTitle, cleanBody]);
      await _runSimple('notify-send', args);
    }
  }

  // ── Open / reveal ─────────────────────────────────────────────────────

  @override
  Future<void> openUrl(String url) async {
    final trimmed = url.trim();
    if (!isAllowedBrowserUrl(trimmed)) {
      throw ArgumentError(
        'Blocked unsafe URL scheme or format in openUrl: only http, https, and mailto are allowed',
      );
    }
    if (_platform == NativePlatform.macos) {
      await _runSimple('open', [trimmed]);
    } else if (_platform == NativePlatform.linux) {
      await _runSimple('xdg-open', [trimmed]);
    } else if (_platform == NativePlatform.windows) {
      await _runSimple('rundll32', ['url.dll,FileProtocolHandler', trimmed]);
    }
  }

  @override
  Future<void> openInEditor(String path, {int? line, int? column}) async {
    if (!_isSafeLocalPathArg(path)) {
      throw ArgumentError('Invalid file path for openInEditor');
    }
    final rawEditor = (Platform.environment['EDITOR'] ?? 'code').trim();
    final editor = NeomageNetworkGuard.isSafeMcpCommand(rawEditor)
        ? rawEditor
        : 'code';
    final args = <String>[];

    if (editor.contains('code') || editor.contains('cursor')) {
      // VS Code / Cursor support --goto file:line:column.
      final loc = StringBuffer(path);
      if (line != null && line > 0) loc.write(':$line');
      if (column != null && column > 0) loc.write(':$column');
      args.addAll(['--goto', loc.toString()]);
    } else {
      args.addAll(['--', path]);
    }

    await _runSimple(editor, args);
  }

  @override
  Future<void> revealInFinder(String path) async {
    if (!_isSafeLocalPathArg(path)) {
      throw ArgumentError('Invalid file path for revealInFinder');
    }
    if (_platform == NativePlatform.macos) {
      await _runSimple('open', ['-R', '--', path]);
    } else if (_platform == NativePlatform.linux) {
      final parentPath = File(path).parent.path;
      if (_isSafeLocalPathArg(parentPath)) {
        await _runSimple('xdg-open', [parentPath]);
      }
    } else if (_platform == NativePlatform.windows) {
      await _runSimple('explorer', ['/select,', path]);
    }
  }

  // ── Environment ───────────────────────────────────────────────────────

  @override
  String? getEnvironmentVariable(String name) => Platform.environment[name];

  // ── Process ───────────────────────────────────────────────────────────

  @override
  Future<void> executeDetached(String command, List<String> args) async {
    if (!NeomageNetworkGuard.isSafeMcpCommand(command)) {
      throw ArgumentError('Blocked unsafe executable in executeDetached');
    }
    if (args.any((a) => a.contains('\x00'))) {
      throw ArgumentError('Blocked NUL byte in executeDetached arguments');
    }
    await Process.start(
      command,
      args,
      mode: ProcessStartMode.detached,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(
        Platform.environment,
      ),
    );
  }

  // ── Global hotkeys ────────────────────────────────────────────────────

  @override
  void registerGlobalHotkey(
    String key,
    List<String> modifiers,
    void Function() callback,
  ) {
    final id = '${modifiers.join("+")}+$key';
    _hotkeys[id] = callback;
    // Actual global hotkey registration requires a native plugin.
    // This stores the intent so a plugin can consume it.
  }

  @override
  void unregisterGlobalHotkey(String key) {
    _hotkeys.removeWhere((k, _) => k.endsWith('+$key'));
  }

  // ── Private helpers ───────────────────────────────────────────────────

  static NativePlatform _detectPlatform() {
    if (Platform.isMacOS) return NativePlatform.macos;
    if (Platform.isLinux) return NativePlatform.linux;
    if (Platform.isWindows) return NativePlatform.windows;
    if (Platform.isAndroid) return NativePlatform.android;
    if (Platform.isIOS) return NativePlatform.ios;
    return NativePlatform.linux; // Fallback.
  }

  Future<String> _runSimple(
    String cmd,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!NeomageNetworkGuard.isSafeMcpCommand(cmd)) return '';
    try {
      final proc = await Process.start(
        cmd,
        args,
        environment: NeomageNetworkGuard.sanitizeSubprocessEnv(
          Platform.environment,
        ),
      );
      final chunks = <int>[];
      const maxBytes = 2 * 1024 * 1024;
      final sub = proc.stdout.listen((chunk) {
        if (chunks.length < maxBytes) {
          final rem = maxBytes - chunks.length;
          chunks.addAll(chunk.length <= rem ? chunk : chunk.sublist(0, rem));
        }
      });
      final errSub = proc.stderr.listen((_) {});
      try {
        await proc.exitCode.timeout(
          timeout,
          onTimeout: () {
            proc.kill();
            return -1;
          },
        );
      } finally {
        await sub.cancel();
        await errSub.cancel();
      }
      return utf8.decode(chunks, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  Future<void> _runPiped(
    String cmd,
    String input, {
    List<String> args = const [],
  }) async {
    if (!NeomageNetworkGuard.isSafeMcpCommand(cmd)) return;
    final process = await Process.start(
      cmd,
      args,
      environment: NeomageNetworkGuard.sanitizeSubprocessEnv(
        Platform.environment,
      ),
    );
    process.stdin.write(input);
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }

  Future<List<String>?> _macosFileDialog({
    String? title,
    List<String>? filters,
    bool multiple = false,
    bool directory = false,
  }) async {
    final result = await _runSimple(
      'osascript',
      buildMacOsFileDialogArgs(
        title: title,
        filters: filters,
        multiple: multiple,
        directory: directory,
      ),
      timeout: const Duration(seconds: 120),
    );
    if (result.trim().isEmpty) return null;

    // osascript returns alias paths — convert.
    return result
        .trim()
        .split(', ')
        .map((p) => p.replaceAll('alias ', '').replaceAll(':', '/'))
        .toList();
  }

  Future<List<String>?> _zenityFileDialog({
    String? title,
    List<String>? filters,
    bool multiple = false,
    bool directory = false,
  }) async {
    final args = <String>['--file-selection'];
    if (title != null) {
      args.add('--title=${title.replaceAll('\x00', '')}');
    }
    if (multiple) args.add('--multiple');
    if (directory) args.add('--directory');
    if (filters != null) {
      for (final f in filters) {
        final trimmed = f.trim();
        if (_safeFilterToken.hasMatch(trimmed)) {
          args.add('--file-filter=*.$trimmed');
        }
      }
    }

    final result = await _runSimple(
      'zenity',
      args,
      timeout: const Duration(seconds: 120),
    );
    if (result.trim().isEmpty) return null;
    return result.trim().split('|');
  }
}

// ── Web stub ───────────────────────────────────────────────────────────────

/// Stub bridge for web — most native operations are unavailable.
class WebNativeBridge implements NativeBridge {
  @override
  NativePlatform getPlatform() => NativePlatform.web;

  @override
  NativeCapabilities getCapabilities() => const NativeCapabilities(
    clipboard: true, // navigator.clipboard available in browsers.
    notifications: true, // Notification API.
    fileDialog: false,
    tray: false,
    globalHotkeys: false,
    biometrics: false,
  );

  @override
  Future<SystemInfo> getSystemInfo() async => const SystemInfo(
    os: 'web',
    version: 'unknown',
    arch: 'unknown',
    hostname: 'browser',
    cpuCores: 0,
    memoryBytes: 0,
    shell: 'none',
  );

  @override
  Future<List<String>?> showFileDialog({
    String? title,
    List<String>? filters,
    bool multiple = false,
    bool directory = false,
  }) async => null;

  @override
  Future<String?> showSaveDialog({
    String? title,
    String? defaultName,
    List<String>? filters,
  }) async => null;

  @override
  Future<void> setClipboard(String text) async {
    // In a real Flutter web app this would call
    // html.window.navigator.clipboard.writeText(text).
  }

  @override
  Future<String?> getClipboard() async => null;

  @override
  Future<void> showNativeNotification(
    String title,
    String body, {
    String? icon,
    bool sound = false,
  }) async {
    // In a real Flutter web app this would use the Notification API.
  }

  @override
  Future<void> openUrl(String url) async {
    // In a real Flutter web app: html.window.open(url, '_blank').
  }

  @override
  Future<void> openInEditor(String path, {int? line, int? column}) async {
    // Not available on web.
  }

  @override
  Future<void> revealInFinder(String path) async {
    // Not available on web.
  }

  @override
  String? getEnvironmentVariable(String name) => null;

  @override
  Future<void> executeDetached(String command, List<String> args) async {
    // Not available on web.
  }

  @override
  void registerGlobalHotkey(
    String key,
    List<String> modifiers,
    void Function() callback,
  ) {
    // Not available on web — keyboard shortcuts should use Flutter's
    // FocusNode / Shortcuts widget instead.
  }

  @override
  void unregisterGlobalHotkey(String key) {
    // No-op on web.
  }
}
