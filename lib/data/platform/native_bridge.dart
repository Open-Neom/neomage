// Native bridge — port of neomage/src/native-ts/.
// Platform-specific native bindings: file dialogs, clipboard, notifications,
// hotkeys, and system info.  Provides a concrete DesktopNativeBridge for
// macOS/Linux/Windows and a stub WebNativeBridge.

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

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

  @override
  Future<String?> showSaveDialog({
    String? title,
    String? defaultName,
    List<String>? filters,
  }) async {
    if (_platform == NativePlatform.macos) {
      final script = StringBuffer('choose file name');
      if (title != null) script.write(' with prompt "$title"');
      if (defaultName != null) script.write(' default name "$defaultName"');
      final result = await _runSimple('osascript', ['-e', script.toString()]);
      return result.trim().isEmpty ? null : result.trim();
    }
    return null;
  }

  // ── Clipboard ─────────────────────────────────────────────────────────

  @override
  Future<void> setClipboard(String text) async {
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
      final soundPart = sound ? ' sound name "default"' : '';
      final script =
          'display notification "$body" with title "$title"$soundPart';
      await _runSimple('osascript', ['-e', script]);
    } else if (_platform == NativePlatform.linux) {
      final args = <String>[title, body];
      if (icon != null) args.addAll(['-i', icon]);
      await _runSimple('notify-send', args);
    }
  }

  // ── Open / reveal ─────────────────────────────────────────────────────

  @override
  Future<void> openUrl(String url) async {
    final cmd = switch (_platform) {
      NativePlatform.macos => 'open',
      NativePlatform.linux => 'xdg-open',
      NativePlatform.windows => 'start',
      _ => null,
    };
    if (cmd != null) await _runSimple(cmd, [url]);
  }

  @override
  Future<void> openInEditor(String path, {int? line, int? column}) async {
    final editor = Platform.environment['EDITOR'] ?? 'code';
    final args = <String>[];

    if (editor.contains('code') || editor.contains('cursor')) {
      // VS Code / Cursor support --goto file:line:column.
      final loc = StringBuffer(path);
      if (line != null) loc.write(':$line');
      if (column != null) loc.write(':$column');
      args.addAll(['--goto', loc.toString()]);
    } else {
      // Fallback: just open the file.
      args.add(path);
    }

    await _runSimple(editor, args);
  }

  @override
  Future<void> revealInFinder(String path) async {
    if (_platform == NativePlatform.macos) {
      await _runSimple('open', ['-R', path]);
    } else if (_platform == NativePlatform.linux) {
      await _runSimple('xdg-open', [File(path).parent.path]);
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
    await Process.start(command, args, mode: ProcessStartMode.detached);
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

  Future<String> _runSimple(String cmd, List<String> args) async {
    try {
      final result = await Process.run(cmd, args);
      return result.stdout.toString();
    } catch (_) {
      return '';
    }
  }

  Future<void> _runPiped(
    String cmd,
    String input, {
    List<String> args = const [],
  }) async {
    final process = await Process.start(cmd, args);
    process.stdin.write(input);
    await process.stdin.close();
    await process.exitCode;
  }

  Future<List<String>?> _macosFileDialog({
    String? title,
    List<String>? filters,
    bool multiple = false,
    bool directory = false,
  }) async {
    final script = StringBuffer();
    if (directory) {
      script.write('choose folder');
    } else {
      script.write('choose file');
    }
    if (title != null) script.write(' with prompt "$title"');
    if (multiple && !directory) {
      script.write(' with multiple selections allowed');
    }
    if (filters != null && filters.isNotEmpty && !directory) {
      final types = filters.map((f) => '"$f"').join(', ');
      script.write(' of type {$types}');
    }

    final result = await _runSimple('osascript', ['-e', script.toString()]);
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
    if (title != null) args.add('--title=$title');
    if (multiple) args.add('--multiple');
    if (directory) args.add('--directory');
    if (filters != null) {
      for (final f in filters) {
        args.add('--file-filter=*.$f');
      }
    }

    final result = await _runSimple('zenity', args);
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
