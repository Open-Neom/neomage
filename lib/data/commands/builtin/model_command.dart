// /model command — switch the active model.

import '../../tools/tool.dart';
import '../command.dart';

/// Callback to change the active model.
typedef ModelChanger = void Function(String model);

class ModelCommand extends LocalCommand {
  final ModelChanger onModelChange;
  final String Function() getCurrentModel;

  ModelCommand({required this.onModelChange, required this.getCurrentModel});

  @override
  String get name => 'model';

  @override
  String get description => 'Switch the active model';

  @override
  String? get argumentHint => '<model-name>';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    if (args.trim().isEmpty) {
      return TextCommandResult(
        'Current model: ${getCurrentModel()}\n'
        'Usage: /model <model-name>',
      );
    }

    final newModel = args.trim();
    onModelChange(newModel);
    return TextCommandResult('Model switched to: $newModel');
  }
}
