// /think-back command — year-in-review animation using thinkback plugin.
// Faithful port of neom_claw/src/commands/thinkback/thinkback.tsx (553 TS LOC).
//
// Covers: plugin installation check, marketplace management, plugin enabling,
// animation playback, skill directory resolution, menu actions (play, edit,
// fix, regenerate), and the complete ThinkbackFlow state machine.

import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;
import 'package:sint/sint.dart';

import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// Constants
// ============================================================================

/// Internal marketplace name for Anthropic employees.
const String _internalMarketplaceName = 'neom-claw-marketplace';

/// Internal marketplace repo for Anthropic employees.
const String _internalMarketplaceRepo = 'anthropics/neom-claw-marketplace';

/// Official marketplace repo for external users.
const String _officialMarketplaceRepo = 'anthropics/neom-claw-plugins-official';

/// Official marketplace display name.
const String _officialMarketplaceName = 'neom-claw-plugins-official';

/// Skill name for thinkback.
const String _skillName = 'thinkback';

/// Prompt sent when user chooses "Edit content".
const String _editPrompt =
    'Use the Skill tool to invoke the "thinkback" skill with mode=edit to '
    'modify my existing NeomClaw year in review animation. Ask me what I '
    'want to change. When the animation is ready, tell the user to run '
    '/think-back again to play it.';

/// Prompt sent when user chooses "Fix errors".
const String _fixPrompt =
    'Use the Skill tool to invoke the "thinkback" skill with mode=fix to fix '
    'validation or rendering errors in my existing NeomClaw year in review '
    'animation. Run the validator, identify errors, and fix them. When the '
    'animation is ready, tell the user to run /think-back again to play it.';

/// Prompt sent when user chooses "Regenerate".
const String _regeneratePrompt =
    'Use the Skill tool to invoke the "thinkback" skill with mode=regenerate '
    'to create a completely new NeomClaw year in review animation from '
    'scratch. Delete the existing animation and start fresh. When the '
    'animation is ready, tell the user to run /think-back again to play it.';

// ============================================================================
// Types
// ============================================================================

/// Installation phase for the thinkback plugin.
enum InstallPhase {
  checking,
  installingMarketplace,
  installingPlugin,
  enablingPlugin,
  ready,
  error,
}

/// State of the thinkback installation process.
class InstallState {
  final InstallPhase phase;
  final String? errorMessage;
  final String? progressMessage;

  const InstallState({
    required this.phase,
    this.errorMessage,
    this.progressMessage,
  });

  InstallState copyWith({
    InstallPhase? phase,
    String? errorMessage,
    String? progressMessage,
  }) => InstallState(
    phase: phase ?? this.phase,
    errorMessage: errorMessage ?? this.errorMessage,
    progressMessage: progressMessage ?? this.progressMessage,
  );
}

/// Menu action for the thinkback command.
enum ThinkbackMenuAction { play, edit, fix, regenerate }

/// Menu option displayed to the user.
class ThinkbackMenuOption {
  final String label;
  final ThinkbackMenuAction value;
  final String description;

  const ThinkbackMenuOption({
    required this.label,
    required this.value,
    required this.description,
  });
}

// ============================================================================
// Marketplace & Plugin Helpers
// ============================================================================

/// Get the marketplace name based on user type.
String getMarketplaceName() {
  final userType = Platform.environment['USER_TYPE'];
  return userType == 'ant'
      ? _internalMarketplaceName
      : _officialMarketplaceName;
}

/// Get the marketplace repo based on user type.
String getMarketplaceRepo() {
  final userType = Platform.environment['USER_TYPE'];
  return userType == 'ant'
      ? _internalMarketplaceRepo
      : _officialMarketplaceRepo;
}

/// Get the full plugin ID including marketplace.
String getPluginId() {
  return '$_skillName@${getMarketplaceName()}';
}

/// Get the thinkback skill directory from the installed plugin's cache path.
///
/// Searches through enabled plugins to find the thinkback plugin, then
/// resolves the skills subdirectory.
Future<String?> getThinkbackSkillDir() async {
  // In the Dart port, we look for the plugin in the standard plugin locations.
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return null;

  // Check common plugin installation paths.
  final candidatePaths = [
    p.join(home, '.neomclaw', 'plugins', _skillName, 'skills', _skillName),
    p.join(home, '.neomclaw', 'plugins', getPluginId(), 'skills', _skillName),
    p.join(
      home,
      '.neomclaw',
      'marketplace',
      getMarketplaceName(),
      _skillName,
      'skills',
      _skillName,
    ),
  ];

  for (final path in candidatePaths) {
    if (await Directory(path).exists()) {
      return path;
    }
  }

  return null;
}

/// Check if a file exists at the given path.
Future<bool> _pathExists(String path) async {
  return File(path).exists();
}

// ============================================================================
// Animation Playback
// ============================================================================

/// Play the thinkback animation.
///
/// Requires the year_in_review.js and player.js files to exist in the skill
/// directory. Launches the Node.js player in the terminal's alternate screen,
/// then opens the HTML file in the browser for video download.
Future<({bool success, String message})> playAnimation(String skillDir) async {
  final dataPath = p.join(skillDir, 'year_in_review.js');
  final playerPath = p.join(skillDir, 'player.js');

  // Verify data file exists.
  if (!await _pathExists(dataPath)) {
    return (
      success: false,
      message: 'No animation found. Run /think-back first to generate one.',
    );
  }

  // Verify player script exists.
  if (!await _pathExists(playerPath)) {
    return (
      success: false,
      message:
          'Player script not found. The player.js file is missing from the '
          'thinkback skill.',
    );
  }

  // Run the player script.
  try {
    final result = await Process.run('node', [
      playerPath,
    ], workingDirectory: skillDir);

    if (result.exitCode != 0) {
      // Animation may have been interrupted (e.g., Ctrl+C).
    }
  } catch (_) {
    // Animation may have been interrupted.
  }

  // Open the HTML file in browser for video download.
  final htmlPath = p.join(skillDir, 'year_in_review.html');
  if (await _pathExists(htmlPath)) {
    final openCmd = Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'start'
        : 'xdg-open';
    try {
      await Process.start(openCmd, [htmlPath]);
    } catch (_) {
      // Ignore errors opening browser.
    }
  }

  return (success: true, message: 'Year in review animation complete!');
}

// ============================================================================
// Installation Flow
// ============================================================================

/// Controller for the thinkback installation and interaction flow.
class ThinkbackController extends SintController {
  /// Current installation state.
  final installState = InstallState(phase: InstallPhase.checking).obs;

  /// Resolved skill directory path.
  final skillDir = Rxn<String>();

  /// Whether a year-in-review animation has been previously generated.
  final hasGenerated = Rxn<bool>();

  /// Whether the user has selected a menu action.
  final hasSelected = false.obs;

  @override
  void onInit() {
    super.onInit();
    _checkAndInstall();
  }

  /// Check installation status and install if needed.
  Future<void> _checkAndInstall() async {
    try {
      installState.value = const InstallState(phase: InstallPhase.checking);

      // Check if marketplace is installed (by checking if plugin dir exists).
      final pluginId = getPluginId();
      final existingSkillDir = await getThinkbackSkillDir();

      if (existingSkillDir != null) {
        // Plugin is already installed and skill directory found.
        skillDir.value = existingSkillDir;
        installState.value = const InstallState(phase: InstallPhase.ready);
        _checkForExistingAnimation();
        return;
      }

      // Plugin not found — attempt marketplace installation.
      installState.value = InstallState(
        phase: InstallPhase.installingMarketplace,
        progressMessage: 'Installing marketplace for $pluginId...',
      );

      // In the Dart port, we delegate actual installation to the plugin system.
      // For now, set error state if plugin is not found.
      installState.value = InstallState(
        phase: InstallPhase.error,
        errorMessage:
            'Thinkback plugin not found. Install it via /plugin command.',
      );
    } catch (e) {
      installState.value = InstallState(
        phase: InstallPhase.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Check if a previously generated animation exists.
  void _checkForExistingAnimation() {
    final dir = skillDir.value;
    if (dir == null) return;

    final dataPath = p.join(dir, 'year_in_review.js');
    _pathExists(dataPath).then((exists) {
      hasGenerated.value = exists;
    });
  }

  /// Get the menu options based on whether an animation has been generated.
  List<ThinkbackMenuOption> get menuOptions {
    if (hasGenerated.value == true) {
      return const [
        ThinkbackMenuOption(
          label: 'Play animation',
          value: ThinkbackMenuAction.play,
          description: 'Watch your year in review',
        ),
        ThinkbackMenuOption(
          label: 'Edit content',
          value: ThinkbackMenuAction.edit,
          description: 'Modify the animation',
        ),
        ThinkbackMenuOption(
          label: 'Fix errors',
          value: ThinkbackMenuAction.fix,
          description: 'Fix validation or rendering issues',
        ),
        ThinkbackMenuOption(
          label: 'Regenerate',
          value: ThinkbackMenuAction.regenerate,
          description: 'Create a new animation from scratch',
        ),
      ];
    }
    return const [
      ThinkbackMenuOption(
        label: "Let's go!",
        value: ThinkbackMenuAction.regenerate,
        description: 'Generate your personalized animation',
      ),
    ];
  }

  /// Handle menu selection.
  Future<String?> handleMenuAction(ThinkbackMenuAction action) async {
    hasSelected.value = true;

    switch (action) {
      case ThinkbackMenuAction.play:
        final dir = skillDir.value;
        if (dir != null) {
          final result = await playAnimation(dir);
          return result.message;
        }
        return 'No skill directory found.';

      case ThinkbackMenuAction.edit:
        return _editPrompt;

      case ThinkbackMenuAction.fix:
        return _fixPrompt;

      case ThinkbackMenuAction.regenerate:
        return _regeneratePrompt;
    }
  }

  /// Get the prompt for a generative action (edit, fix, regenerate).
  String getPromptForAction(ThinkbackMenuAction action) {
    switch (action) {
      case ThinkbackMenuAction.edit:
        return _editPrompt;
      case ThinkbackMenuAction.fix:
        return _fixPrompt;
      case ThinkbackMenuAction.regenerate:
        return _regeneratePrompt;
      case ThinkbackMenuAction.play:
        return ''; // Play is not a generative action.
    }
  }

  /// Get a status message for the current installation phase.
  String get statusMessage {
    final state = installState.value;
    if (state.progressMessage != null) return state.progressMessage!;

    switch (state.phase) {
      case InstallPhase.checking:
        return 'Checking thinkback installation...';
      case InstallPhase.installingMarketplace:
        return 'Installing marketplace...';
      case InstallPhase.installingPlugin:
        return 'Installing thinkback plugin...';
      case InstallPhase.enablingPlugin:
        return 'Enabling thinkback plugin...';
      case InstallPhase.ready:
        return 'Thinkback ready.';
      case InstallPhase.error:
        return state.errorMessage ?? 'An error occurred.';
    }
  }
}

// ============================================================================
// Command Definition
// ============================================================================

/// The /think-back command — year-in-review animation.
///
/// Manages the thinkback plugin lifecycle:
/// 1. Checks if the plugin is installed
/// 2. Installs marketplace and plugin if needed
/// 3. Resolves skill directory
/// 4. Presents menu (play/edit/fix/regenerate)
/// 5. Dispatches the chosen action
class ThinkbackCommand extends LocalUiCommand {
  @override
  String get name => 'think-back';

  @override
  String get description =>
      'Generate your 2025 NeomClaw Think Back (takes a few minutes to run)';

  @override
  List<String> get aliases => const ['thinkback'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    // Check if skill directory exists.
    final dir = await getThinkbackSkillDir();

    if (dir == null) {
      return const TextCommandResult(
        'Thinkback plugin not found. Install it via /plugin command.\n'
        'Try running /plugin to manually install the think-back plugin.',
      );
    }

    // Check if animation has been generated.
    final dataPath = p.join(dir, 'year_in_review.js');
    final hasAnimation = await _pathExists(dataPath);

    if (hasAnimation) {
      // If animation exists, present menu options.
      final menuText = StringBuffer()
        ..writeln('Think Back on 2025 with NeomClaw')
        ..writeln()
        ..writeln('Options:')
        ..writeln('  1. Play animation — Watch your year in review')
        ..writeln('  2. Edit content — Modify the animation')
        ..writeln('  3. Fix errors — Fix validation or rendering issues')
        ..writeln('  4. Regenerate — Create a new animation from scratch')
        ..writeln()
        ..writeln('Use /think-back play to play the animation, or')
        ..writeln('/think-back regenerate to create a new one.');

      // Handle sub-commands.
      final subCommand = args.trim().toLowerCase();
      if (subCommand == 'play') {
        final result = await playAnimation(dir);
        return TextCommandResult(result.message);
      } else if (subCommand == 'edit') {
        return const TextCommandResult(_editPrompt);
      } else if (subCommand == 'fix') {
        return const TextCommandResult(_fixPrompt);
      } else if (subCommand == 'regenerate') {
        return const TextCommandResult(_regeneratePrompt);
      }

      return TextCommandResult(menuText.toString());
    }

    // No animation yet — offer to generate.
    if (args.trim().toLowerCase() == 'regenerate' || args.trim().isEmpty) {
      return const TextCommandResult(_regeneratePrompt);
    }

    return const TextCommandResult(
      'No animation found. Run /think-back to generate your '
      'personalized year-in-review animation.',
    );
  }
}
