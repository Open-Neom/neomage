// Platform bridge — port of neom_claw platform-specific abstractions.
// Provides unified API across desktop, mobile, web, and CLI.

import 'package:neom_claw/core/platform/claw_io.dart';

/// Supported platforms.
enum ClawPlatform {
  macOS,
  linux,
  windows,
  android,
  iOS,
  web,
  cli,
}

/// Platform capabilities — what the current platform supports.
class PlatformCapabilities {
  final bool hasFileSystem;
  final bool hasProcessSpawn;
  final bool hasStdin;
  final bool hasClipboard;
  final bool hasNotifications;
  final bool hasWindowManagement;
  final bool hasTouchInput;
  final bool hasKeyboard;
  final bool hasVoiceInput;
  final bool hasBiometrics;

  const PlatformCapabilities({
    this.hasFileSystem = true,
    this.hasProcessSpawn = true,
    this.hasStdin = true,
    this.hasClipboard = true,
    this.hasNotifications = true,
    this.hasWindowManagement = true,
    this.hasTouchInput = false,
    this.hasKeyboard = true,
    this.hasVoiceInput = false,
    this.hasBiometrics = false,
  });

  factory PlatformCapabilities.desktop() => const PlatformCapabilities(
        hasFileSystem: true,
        hasProcessSpawn: true,
        hasStdin: true,
        hasClipboard: true,
        hasNotifications: true,
        hasWindowManagement: true,
        hasTouchInput: false,
        hasKeyboard: true,
      );

  factory PlatformCapabilities.mobile() => const PlatformCapabilities(
        hasFileSystem: true,
        hasProcessSpawn: false,
        hasStdin: false,
        hasClipboard: true,
        hasNotifications: true,
        hasWindowManagement: false,
        hasTouchInput: true,
        hasKeyboard: true,
        hasVoiceInput: true,
        hasBiometrics: true,
      );

  factory PlatformCapabilities.web() => const PlatformCapabilities(
        hasFileSystem: false,
        hasProcessSpawn: false,
        hasStdin: false,
        hasClipboard: true,
        hasNotifications: true,
        hasWindowManagement: false,
        hasTouchInput: false,
        hasKeyboard: true,
      );

  factory PlatformCapabilities.cli() => const PlatformCapabilities(
        hasFileSystem: true,
        hasProcessSpawn: true,
        hasStdin: true,
        hasClipboard: false,
        hasNotifications: false,
        hasWindowManagement: false,
        hasTouchInput: false,
        hasKeyboard: true,
      );
}

/// Platform bridge — detects current platform and provides capabilities.
class PlatformBridge {
  late final ClawPlatform platform;
  late final PlatformCapabilities capabilities;
  final Map<String, String> _environment;
  final String _homeDir;
  final String _configDir;

  PlatformBridge._({
    required this.platform,
    required this.capabilities,
    required Map<String, String> environment,
    required String homeDir,
    required String configDir,
  })  : _environment = environment,
        _homeDir = homeDir,
        _configDir = configDir;

  /// Create with auto-detection.
  factory PlatformBridge.detect() {
    final platform = _detectPlatform();
    final capabilities = _capabilitiesFor(platform);
    final env = Platform.environment;
    final home = _resolveHomeDir(env);
    final config = _resolveConfigDir(env, home);

    return PlatformBridge._(
      platform: platform,
      capabilities: capabilities,
      environment: env,
      homeDir: home,
      configDir: config,
    );
  }

  /// Create for a specific platform (testing).
  factory PlatformBridge.forPlatform(ClawPlatform platform) {
    return PlatformBridge._(
      platform: platform,
      capabilities: _capabilitiesFor(platform),
      environment: Platform.environment,
      homeDir: _resolveHomeDir(Platform.environment),
      configDir: _resolveConfigDir(
        Platform.environment,
        _resolveHomeDir(Platform.environment),
      ),
    );
  }

  /// Home directory.
  String get homeDir => _homeDir;

  /// Config directory (~/.neomclaw).
  String get configDir => _configDir;

  /// Environment variables.
  Map<String, String> get environment => Map.unmodifiable(_environment);

  /// Get an environment variable.
  String? env(String key) => _environment[key];

  /// Whether running on desktop.
  bool get isDesktop =>
      platform == ClawPlatform.macOS ||
      platform == ClawPlatform.linux ||
      platform == ClawPlatform.windows;

  /// Whether running on mobile.
  bool get isMobile =>
      platform == ClawPlatform.android || platform == ClawPlatform.iOS;

  /// Whether running in CLI/headless mode.
  bool get isCli => platform == ClawPlatform.cli;

  /// Whether the tool system is available (needs process spawning).
  bool get canRunTools => capabilities.hasProcessSpawn;

  /// Whether MCP servers can be started.
  bool get canRunMcp => capabilities.hasProcessSpawn;

  /// Whether LSP servers can be started.
  bool get canRunLsp => capabilities.hasProcessSpawn;

  /// Whether local file operations work.
  bool get canAccessFiles => capabilities.hasFileSystem;

  /// Resolve a path relative to home.
  String resolvePath(String path) {
    if (path.startsWith('~/')) {
      return '$_homeDir${path.substring(1)}';
    }
    return path;
  }

  /// Get the shell for the current platform.
  String get defaultShell {
    if (platform == ClawPlatform.windows) {
      return _environment['COMSPEC'] ?? 'cmd.exe';
    }
    return _environment['SHELL'] ?? '/bin/sh';
  }

  /// Path separator for the current platform.
  String get pathSeparator =>
      platform == ClawPlatform.windows ? '\\' : '/';

  /// Get platform-appropriate temp directory.
  String get tempDir => Directory.systemTemp.path;

  // ── Private ──

  static ClawPlatform _detectPlatform() {
    // Check for CLI mode via env var
    if (Platform.environment.containsKey('CLAW_CLI_MODE')) {
      return ClawPlatform.cli;
    }

    if (Platform.isMacOS) return ClawPlatform.macOS;
    if (Platform.isLinux) return ClawPlatform.linux;
    if (Platform.isWindows) return ClawPlatform.windows;
    if (Platform.isAndroid) return ClawPlatform.android;
    if (Platform.isIOS) return ClawPlatform.iOS;

    return ClawPlatform.cli; // Fallback
  }

  static PlatformCapabilities _capabilitiesFor(ClawPlatform platform) {
    return switch (platform) {
      ClawPlatform.macOS ||
      ClawPlatform.linux ||
      ClawPlatform.windows =>
        PlatformCapabilities.desktop(),
      ClawPlatform.android || ClawPlatform.iOS => PlatformCapabilities.mobile(),
      ClawPlatform.web => PlatformCapabilities.web(),
      ClawPlatform.cli => PlatformCapabilities.cli(),
    };
  }

  static String _resolveHomeDir(Map<String, String> env) {
    return env['HOME'] ?? env['USERPROFILE'] ?? '/tmp';
  }

  static String _resolveConfigDir(Map<String, String> env, String home) {
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null) return '$xdg/neomclaw';
    return '/.neomclaw';
  }
}

/// Platform-specific path utilities.
class PlatformPaths {
  final PlatformBridge bridge;

  const PlatformPaths(this.bridge);

  /// Global settings file.
  String get settingsFile => '${bridge.configDir}/settings.json';

  /// Project-level settings.
  String projectSettings(String projectDir) =>
      '$projectDir/.neomclaw/settings.json';

  /// MCP config file.
  String get mcpConfigFile => '${bridge.configDir}/.mcp.json';

  /// Project-level MCP config.
  String projectMcpConfig(String projectDir) => '$projectDir/.mcp.json';

  /// Keybindings file.
  String get keybindingsFile => '${bridge.configDir}/keybindings.json';

  /// Session storage directory.
  String get sessionsDir => '${bridge.configDir}/sessions';

  /// Memory directory.
  String get memoryDir => '${bridge.configDir}/memory';

  /// Plugins directory.
  String get pluginsDir => '${bridge.configDir}/plugins';

  /// Analytics directory.
  String get analyticsDir => '${bridge.configDir}/analytics';

  /// Log file.
  String get logFile => '${bridge.configDir}/claw.log';

  /// Credentials file.
  String get credentialsFile => '${bridge.configDir}/credentials.json';
}
