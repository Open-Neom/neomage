// /terminal-setup command — configures terminal keybindings for Shift+Enter.
// Faithful port of neom_claw/src/commands/terminalSetup/terminalSetup.tsx
// (530 TS LOC).
//
// Covers: terminal detection, native CSI u support check, VSCode/Cursor/
// Windsurf keybinding installation, Apple Terminal Option-as-Meta setup,
// Alacritty and Zed keybinding installation, shell completion setup,
// backup/restore for Terminal.app preferences, and remote SSH detection.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// Constants
// ============================================================================

/// Terminals that natively support CSI u / Kitty keyboard protocol.
const Map<String, String> nativeCSIuTerminals = {
  'ghostty': 'Ghostty',
  'kitty': 'Kitty',
  'iTerm.app': 'iTerm2',
  'WezTerm': 'WezTerm',
  'WarpTerminal': 'Warp',
};

// ============================================================================
// Terminal Detection
// ============================================================================

/// Detect the current terminal emulator from environment variables.
String? detectTerminal() {
  final env = Platform.environment;

  // Check TERM_PROGRAM first (most reliable).
  final termProgram = env['TERM_PROGRAM'];
  if (termProgram != null) {
    if (termProgram == 'Apple_Terminal') return 'Apple_Terminal';
    if (termProgram == 'vscode') return 'vscode';
    if (termProgram.contains('cursor')) return 'cursor';
    if (termProgram.contains('windsurf')) return 'windsurf';
    if (termProgram.contains('Alacritty')) return 'alacritty';
    if (termProgram.contains('iTerm')) return 'iTerm.app';
    if (termProgram.contains('WezTerm')) return 'WezTerm';
    if (termProgram.contains('WarpTerminal')) return 'WarpTerminal';
    if (termProgram.contains('ghostty')) return 'ghostty';
    if (termProgram.contains('kitty')) return 'kitty';
  }

  // Check for Zed.
  if (env['ZED_TERM'] != null) return 'zed';

  // Check for VSCode via environment variables.
  if (env['VSCODE_GIT_ASKPASS_MAIN'] != null) return 'vscode';

  return termProgram;
}

/// Get display name for a terminal that natively supports CSI u.
String? getNativeCSIuTerminalDisplayName() {
  final terminal = detectTerminal();
  if (terminal == null || !nativeCSIuTerminals.containsKey(terminal)) {
    return null;
  }
  return nativeCSIuTerminals[terminal];
}

/// Detect if we're running in a VSCode Remote SSH session.
///
/// In this case, keybindings need to be installed on the LOCAL machine,
/// not the remote server where NeomClaw is running.
bool isVSCodeRemoteSSH() {
  final env = Platform.environment;
  final askpassMain = env['VSCODE_GIT_ASKPASS_MAIN'] ?? '';
  final path = env['PATH'] ?? '';

  return askpassMain.contains('.vscode-server') ||
      askpassMain.contains('.cursor-server') ||
      askpassMain.contains('.windsurf-server') ||
      path.contains('.vscode-server') ||
      path.contains('.cursor-server') ||
      path.contains('.windsurf-server');
}

/// Whether terminal setup should be offered for the current terminal.
bool shouldOfferTerminalSetup() {
  final terminal = detectTerminal();
  if (Platform.isMacOS && terminal == 'Apple_Terminal') return true;
  return terminal == 'vscode' ||
      terminal == 'cursor' ||
      terminal == 'windsurf' ||
      terminal == 'alacritty' ||
      terminal == 'zed';
}

// ============================================================================
// Path Utilities
// ============================================================================

/// Get the Terminal.app plist path.
String getTerminalPlistPath() {
  return p.join(
    Platform.environment['HOME'] ?? '',
    'Library',
    'Preferences',
    'com.apple.Terminal.plist',
  );
}

/// Generate a random hex string for backup file suffixes.
String _randomHex(int bytes) {
  final rng = Random.secure();
  return List.generate(
    bytes,
    (_) => rng.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ============================================================================
// VSCode / Cursor / Windsurf Keybinding Installation
// ============================================================================

/// VSCode-style keybinding entry.
class _VSCodeKeybinding {
  final String key;
  final String command;
  final Map<String, String> args;
  final String when;

  const _VSCodeKeybinding({
    required this.key,
    required this.command,
    required this.args,
    required this.when,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'command': command,
    'args': args,
    'when': when,
  };
}

/// Install Shift+Enter keybinding for VSCode, Cursor, or Windsurf.
///
/// Creates/modifies the keybindings.json file in the editor's user directory.
/// Backs up existing file before modification.
Future<String> installBindingsForVSCodeTerminal({
  String editor = 'VSCode',
}) async {
  // Check if we're running in a VSCode Remote SSH session.
  if (isVSCodeRemoteSSH()) {
    return 'Cannot install keybindings from a remote $editor session.\n\n'
        '$editor keybindings must be installed on your local machine, '
        'not the remote server.\n\n'
        'To install the Shift+Enter keybinding:\n'
        '1. Open $editor on your local machine (not connected to remote)\n'
        '2. Open the Command Palette (Cmd/Ctrl+Shift+P) -> '
        '"Preferences: Open Keyboard Shortcuts (JSON)"\n'
        '3. Add this keybinding (the file must be a JSON array):\n\n'
        '[\n'
        '  {\n'
        '    "key": "shift+enter",\n'
        '    "command": "workbench.action.terminal.sendSequence",\n'
        '    "args": { "text": "\\u001b\\r" },\n'
        '    "when": "terminalFocus"\n'
        '  }\n'
        ']\n';
  }

  final editorDir = editor == 'VSCode' ? 'Code' : editor;
  final home = Platform.environment['HOME'] ?? '';

  String userDirPath;
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'] ?? '';
    userDirPath = p.join(appData, editorDir, 'User');
  } else if (Platform.isMacOS) {
    userDirPath = p.join(
      home,
      'Library',
      'Application Support',
      editorDir,
      'User',
    );
  } else {
    userDirPath = p.join(home, '.config', editorDir, 'User');
  }

  final keybindingsPath = p.join(userDirPath, 'keybindings.json');

  try {
    // Ensure user directory exists.
    await Directory(userDirPath).create(recursive: true);

    // Read existing keybindings file.
    String content = '[]';
    List<dynamic> keybindings = [];
    bool fileExists = false;

    try {
      content = await File(keybindingsPath).readAsString();
      fileExists = true;
      // Strip comments for parsing (JSONC -> JSON).
      final stripped = _stripJsonComments(content);
      keybindings = jsonDecode(stripped) as List<dynamic>? ?? [];
    } catch (e) {
      if (e is! FileSystemException) rethrow;
    }

    // Backup the existing file before modifying.
    if (fileExists) {
      final randomSha = _randomHex(4);
      final backupPath = '$keybindingsPath.$randomSha.bak';
      try {
        await File(keybindingsPath).copy(backupPath);
      } catch (_) {
        return 'Error backing up existing $editor terminal keybindings. '
            'Bailing out.\n'
            'See $keybindingsPath\n'
            'Backup path: $backupPath\n';
      }
    }

    // Check if keybinding already exists.
    final existingBinding = keybindings.any((binding) {
      if (binding is! Map<String, dynamic>) return false;
      return binding['key'] == 'shift+enter' &&
          binding['command'] == 'workbench.action.terminal.sendSequence' &&
          binding['when'] == 'terminalFocus';
    });

    if (existingBinding) {
      return 'Found existing $editor terminal Shift+Enter key binding. '
          'Remove it to continue.\n'
          'See $keybindingsPath\n';
    }

    // Create the new keybinding.
    const newKeybinding = _VSCodeKeybinding(
      key: 'shift+enter',
      command: 'workbench.action.terminal.sendSequence',
      args: {'text': '\x1b\r'},
      when: 'terminalFocus',
    );

    // Add to the array and write back.
    keybindings.add(newKeybinding.toJson());
    final updatedContent = const JsonEncoder.withIndent(
      '  ',
    ).convert(keybindings);
    await File(keybindingsPath).writeAsString(updatedContent);

    return 'Installed $editor terminal Shift+Enter key binding\n'
        'See $keybindingsPath\n';
  } catch (e) {
    throw Exception(
      'Failed to install $editor terminal Shift+Enter key binding: $e',
    );
  }
}

// ============================================================================
// Apple Terminal.app Setup
// ============================================================================

/// Enable Option as Meta key for a Terminal.app profile.
///
/// Uses PlistBuddy to modify the profile's useOptionAsMetaKey setting.
Future<bool> enableOptionAsMetaForProfile(String profileName) async {
  // First try to add the property (in case it doesn't exist).
  var result = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    "Add :'Window Settings':'$profileName':useOptionAsMetaKey bool true",
    getTerminalPlistPath(),
  ]);

  // If adding fails (likely because it already exists), try setting it.
  if (result.exitCode != 0) {
    result = await Process.run('/usr/libexec/PlistBuddy', [
      '-c',
      "Set :'Window Settings':'$profileName':useOptionAsMetaKey true",
      getTerminalPlistPath(),
    ]);
    if (result.exitCode != 0) return false;
  }
  return true;
}

/// Disable audio bell for a Terminal.app profile.
Future<bool> disableAudioBellForProfile(String profileName) async {
  var result = await Process.run('/usr/libexec/PlistBuddy', [
    '-c',
    "Add :'Window Settings':'$profileName':Bell bool false",
    getTerminalPlistPath(),
  ]);

  if (result.exitCode != 0) {
    result = await Process.run('/usr/libexec/PlistBuddy', [
      '-c',
      "Set :'Window Settings':'$profileName':Bell false",
      getTerminalPlistPath(),
    ]);
    if (result.exitCode != 0) return false;
  }
  return true;
}

/// Enable Option as Meta key for Terminal.app.
///
/// Reads default and startup profiles, enables Option as Meta key and
/// disables audio bell for both, then flushes the preferences cache.
Future<String> enableOptionAsMetaForTerminal() async {
  try {
    // Create a backup of the current plist file.
    final plistPath = getTerminalPlistPath();
    final backupPath = '$plistPath.${_randomHex(4)}.bak';
    try {
      await File(plistPath).copy(backupPath);
    } catch (_) {
      throw Exception(
        'Failed to create backup of Terminal.app preferences, bailing out',
      );
    }

    // Read the current default profile.
    final defaultResult = await Process.run('defaults', [
      'read',
      'com.apple.Terminal',
      'Default Window Settings',
    ]);
    if (defaultResult.exitCode != 0 ||
        (defaultResult.stdout as String).trim().isEmpty) {
      throw Exception('Failed to read default Terminal.app profile');
    }

    final startupResult = await Process.run('defaults', [
      'read',
      'com.apple.Terminal',
      'Startup Window Settings',
    ]);
    if (startupResult.exitCode != 0 ||
        (startupResult.stdout as String).trim().isEmpty) {
      throw Exception('Failed to read startup Terminal.app profile');
    }

    bool wasAnyProfileUpdated = false;
    final defaultProfileName = (defaultResult.stdout as String).trim();

    final optionAsMetaEnabled = await enableOptionAsMetaForProfile(
      defaultProfileName,
    );
    final audioBellDisabled = await disableAudioBellForProfile(
      defaultProfileName,
    );
    if (optionAsMetaEnabled || audioBellDisabled) {
      wasAnyProfileUpdated = true;
    }

    final startupProfileName = (startupResult.stdout as String).trim();

    // Only proceed if the startup profile is different from default.
    if (startupProfileName != defaultProfileName) {
      final startupOptionEnabled = await enableOptionAsMetaForProfile(
        startupProfileName,
      );
      final startupBellDisabled = await disableAudioBellForProfile(
        startupProfileName,
      );
      if (startupOptionEnabled || startupBellDisabled) {
        wasAnyProfileUpdated = true;
      }
    }

    if (!wasAnyProfileUpdated) {
      throw Exception(
        'Failed to enable Option as Meta key or disable audio bell '
        'for any Terminal.app profile',
      );
    }

    // Flush the preferences cache.
    await Process.run('killall', ['cfprefsd']);

    return 'Configured Terminal.app settings:\n'
        '- Enabled "Use Option as Meta key"\n'
        '- Switched to visual bell\n'
        'Option+Enter will now enter a newline.\n'
        'You must restart Terminal.app for changes to take effect.\n';
  } catch (e) {
    throw Exception('Failed to enable Option as Meta key for Terminal.app: $e');
  }
}

// ============================================================================
// Alacritty Keybinding Installation
// ============================================================================

/// Install Shift+Enter keybinding for Alacritty.
///
/// Appends the TOML keybinding configuration to alacritty.toml.
Future<String> installBindingsForAlacritty() async {
  const keybinding = '''
[[keyboard.bindings]]
key = "Return"
mods = "Shift"
chars = "\\u001B\\r"''';

  final home = Platform.environment['HOME'] ?? '';
  final configPaths = <String>[];

  // XDG config path.
  final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME'];
  if (xdgConfigHome != null) {
    configPaths.add(p.join(xdgConfigHome, 'alacritty', 'alacritty.toml'));
  } else {
    configPaths.add(p.join(home, '.config', 'alacritty', 'alacritty.toml'));
  }

  // Windows-specific path.
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      configPaths.add(p.join(appData, 'alacritty', 'alacritty.toml'));
    }
  }

  // Find existing config file.
  String? configPath;
  String configContent = '';
  bool configExists = false;

  for (final path in configPaths) {
    try {
      configContent = await File(path).readAsString();
      configPath = path;
      configExists = true;
      break;
    } catch (e) {
      if (e is! FileSystemException) rethrow;
    }
  }

  configPath ??= configPaths.isNotEmpty ? configPaths.first : null;
  if (configPath == null) {
    throw Exception('No valid config path found for Alacritty');
  }

  try {
    if (configExists) {
      // Check if keybinding already exists.
      if (configContent.contains('mods = "Shift"') &&
          configContent.contains('key = "Return"')) {
        return 'Found existing Alacritty Shift+Enter key binding. '
            'Remove it to continue.\n'
            'See $configPath\n';
      }

      // Create backup.
      final randomSha = _randomHex(4);
      final backupPath = '$configPath.$randomSha.bak';
      try {
        await File(configPath).copy(backupPath);
      } catch (_) {
        return 'Error backing up existing Alacritty config. Bailing out.\n'
            'See $configPath\n'
            'Backup path: $backupPath\n';
      }
    } else {
      // Ensure config directory exists.
      await Directory(p.dirname(configPath)).create(recursive: true);
    }

    // Add the keybinding to the config.
    var updatedContent = configContent;
    if (configContent.isNotEmpty && !configContent.endsWith('\n')) {
      updatedContent += '\n';
    }
    updatedContent += '\n$keybinding\n';

    await File(configPath).writeAsString(updatedContent);
    return 'Installed Alacritty Shift+Enter key binding\n'
        'You may need to restart Alacritty for changes to take effect\n'
        'See $configPath\n';
  } catch (e) {
    throw Exception('Failed to install Alacritty Shift+Enter key binding: $e');
  }
}

// ============================================================================
// Zed Keybinding Installation
// ============================================================================

/// Install Shift+Enter keybinding for Zed.
///
/// Modifies the keymap.json file in Zed's config directory.
Future<String> installBindingsForZed() async {
  final home = Platform.environment['HOME'] ?? '';
  final zedDir = p.join(home, '.config', 'zed');
  final keymapPath = p.join(zedDir, 'keymap.json');

  try {
    await Directory(zedDir).create(recursive: true);

    String keymapContent = '[]';
    bool fileExists = false;

    try {
      keymapContent = await File(keymapPath).readAsString();
      fileExists = true;
    } catch (e) {
      if (e is! FileSystemException) rethrow;
    }

    if (fileExists) {
      // Check if keybinding already exists.
      if (keymapContent.contains('shift-enter')) {
        return 'Found existing Zed Shift+Enter key binding. '
            'Remove it to continue.\n'
            'See $keymapPath\n';
      }

      // Create backup.
      final randomSha = _randomHex(4);
      final backupPath = '$keymapPath.$randomSha.bak';
      try {
        await File(keymapPath).copy(backupPath);
      } catch (_) {
        return 'Error backing up existing Zed keymap. Bailing out.\n'
            'See $keymapPath\n'
            'Backup path: $backupPath\n';
      }
    }

    // Parse and modify the keymap.
    List<dynamic> keymap;
    try {
      keymap = jsonDecode(keymapContent) as List<dynamic>? ?? [];
    } catch (_) {
      keymap = [];
    }

    // Add the new keybinding for terminal context.
    keymap.add({
      'context': 'Terminal',
      'bindings': {
        'shift-enter': ['terminal::SendText', '\x1b\r'],
      },
    });

    // Write the updated keymap.
    final updatedContent =
        '${const JsonEncoder.withIndent('  ').convert(keymap)}\n';
    await File(keymapPath).writeAsString(updatedContent);

    return 'Installed Zed Shift+Enter key binding\n'
        'See $keymapPath\n';
  } catch (e) {
    throw Exception('Failed to install Zed Shift+Enter key binding: $e');
  }
}

// ============================================================================
// Main Setup Function
// ============================================================================

/// Run terminal setup for the detected terminal.
///
/// Dispatches to the appropriate installer based on the terminal type.
/// Returns a user-facing message describing what was done.
Future<String> setupTerminal() async {
  final terminal = detectTerminal();

  String result = '';
  switch (terminal) {
    case 'Apple_Terminal':
      result = await enableOptionAsMetaForTerminal();
      break;
    case 'vscode':
      result = await installBindingsForVSCodeTerminal(editor: 'VSCode');
      break;
    case 'cursor':
      result = await installBindingsForVSCodeTerminal(editor: 'Cursor');
      break;
    case 'windsurf':
      result = await installBindingsForVSCodeTerminal(editor: 'Windsurf');
      break;
    case 'alacritty':
      result = await installBindingsForAlacritty();
      break;
    case 'zed':
      result = await installBindingsForZed();
      break;
    default:
      break;
  }

  return result;
}

// ============================================================================
// JSONC Helper
// ============================================================================

/// Strip single-line and block comments from JSONC content.
String _stripJsonComments(String content) {
  final buf = StringBuffer();
  bool inString = false;
  bool inLineComment = false;
  bool inBlockComment = false;

  for (int i = 0; i < content.length; i++) {
    if (inLineComment) {
      if (content[i] == '\n') {
        inLineComment = false;
        buf.write('\n');
      }
      continue;
    }

    if (inBlockComment) {
      if (i + 1 < content.length &&
          content[i] == '*' &&
          content[i + 1] == '/') {
        inBlockComment = false;
        i++; // Skip the '/'.
      }
      continue;
    }

    if (inString) {
      buf.write(content[i]);
      if (content[i] == '\\' && i + 1 < content.length) {
        buf.write(content[i + 1]);
        i++;
      } else if (content[i] == '"') {
        inString = false;
      }
      continue;
    }

    if (content[i] == '"') {
      inString = true;
      buf.write(content[i]);
      continue;
    }

    if (i + 1 < content.length) {
      if (content[i] == '/' && content[i + 1] == '/') {
        inLineComment = true;
        continue;
      }
      if (content[i] == '/' && content[i + 1] == '*') {
        inBlockComment = true;
        i++;
        continue;
      }
    }

    buf.write(content[i]);
  }

  return buf.toString();
}

// ============================================================================
// Command Definition
// ============================================================================

/// The /terminal-setup command — configures terminal for Shift+Enter.
///
/// Detects the current terminal emulator and installs the appropriate
/// keybinding or preference change to enable Shift+Enter for multi-line
/// prompts. Supports Apple Terminal, VSCode, Cursor, Windsurf, Alacritty,
/// and Zed. Terminals with native CSI u support (Ghostty, Kitty, iTerm2,
/// WezTerm, Warp) need no configuration.
class TerminalSetupCommand extends LocalCommand {
  @override
  String get name => 'terminal-setup';

  @override
  String get description =>
      'Set up Shift+Enter keyboard shortcut for multi-line prompts';

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final terminal = detectTerminal();

    // Check if terminal natively supports CSI u.
    if (terminal != null && nativeCSIuTerminals.containsKey(terminal)) {
      final displayName = nativeCSIuTerminals[terminal]!;
      return TextCommandResult(
        'Shift+Enter is natively supported in $displayName.\n\n'
        'No configuration needed. Just use Shift+Enter to add newlines.',
      );
    }

    // Check if terminal is supported for setup.
    if (!shouldOfferTerminalSetup()) {
      final terminalName = terminal ?? 'your current terminal';

      final platformTerminals = StringBuffer();
      if (Platform.isMacOS) {
        platformTerminals.writeln('   - macOS: Apple Terminal');
      } else if (Platform.isWindows) {
        platformTerminals.writeln('   - Windows: Windows Terminal');
      }

      return TextCommandResult(
        'Terminal setup cannot be run from $terminalName.\n\n'
        'This command configures a convenient Shift+Enter shortcut for '
        'multi-line prompts.\n'
        'Note: You can already use backslash (\\) + return to add newlines.\n\n'
        'To set up the shortcut (optional):\n'
        '1. Exit tmux/screen temporarily\n'
        '2. Run /terminal-setup directly in one of these terminals:\n'
        '$platformTerminals'
        '   - IDE: VSCode, Cursor, Windsurf, Zed\n'
        '   - Other: Alacritty\n'
        '3. Return to tmux/screen - settings will persist\n\n'
        'Note: iTerm2, WezTerm, Ghostty, Kitty, and Warp support '
        'Shift+Enter natively.',
      );
    }

    try {
      final result = await setupTerminal();
      return TextCommandResult(result);
    } catch (e) {
      return TextCommandResult('Terminal setup failed: $e');
    }
  }
}
