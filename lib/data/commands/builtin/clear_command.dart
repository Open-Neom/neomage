// /clear command — clears conversation history.

import '../../tools/tool.dart';
import '../command.dart';

class ClearCommand extends LocalCommand {
  @override
  String get name => 'clear';

  @override
  String get description => 'Clear conversation history and start fresh';

  @override
  List<String> get aliases => const ['reset', 'new'];

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    return const TextCommandResult('Conversation cleared.');
  }
}
