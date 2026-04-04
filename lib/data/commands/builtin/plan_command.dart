// /plan command — enter plan mode or view session plan.

import '../../tools/tool.dart';
import '../command.dart';

/// Callback for plan mode toggling.
typedef PlanModeToggle = void Function(bool enabled);

class PlanCommand extends LocalCommand {
  final PlanModeToggle onToggle;
  final bool Function() isPlanMode;

  PlanCommand({required this.onToggle, required this.isPlanMode});

  @override
  String get name => 'plan';

  @override
  String get description => 'Toggle plan mode (think before acting)';

  @override
  List<String> get aliases => const ['think'];

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final current = isPlanMode();
    final newState = !current;
    onToggle(newState);

    return TextCommandResult(
      newState
          ? 'Plan mode enabled. I will think through my approach before '
                'making changes. Use /plan again to disable.'
          : 'Plan mode disabled. Returning to normal execution.',
    );
  }
}
