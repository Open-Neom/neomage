// /cost command — show session cost and token usage.

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

class CostCommand extends LocalCommand {
  final List<Message> Function() getMessages;

  CostCommand({required this.getMessages});

  @override
  String get name => 'cost';

  @override
  String get description => 'Show session cost and token usage summary';

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final messages = getMessages();
    var totalInput = 0;
    var totalOutput = 0;
    var totalCacheCreation = 0;
    var totalCacheRead = 0;
    var toolUseCount = 0;

    for (final msg in messages) {
      if (msg.usage != null) {
        totalInput += msg.usage!.inputTokens;
        totalOutput += msg.usage!.outputTokens;
        totalCacheCreation += msg.usage!.cacheCreationInputTokens ?? 0;
        totalCacheRead += msg.usage!.cacheReadInputTokens ?? 0;
      }
      toolUseCount += msg.toolUses.length;
    }

    final buffer = StringBuffer();
    buffer.writeln('Session Usage:');
    buffer.writeln('  Input tokens:  $totalInput');
    buffer.writeln('  Output tokens: $totalOutput');
    if (totalCacheCreation > 0) {
      buffer.writeln('  Cache write:   $totalCacheCreation');
    }
    if (totalCacheRead > 0) {
      buffer.writeln('  Cache read:    $totalCacheRead');
    }
    buffer.writeln('  Total tokens:  ${totalInput + totalOutput}');
    buffer.writeln('  Tool uses:     $toolUseCount');
    buffer.writeln('  Messages:      ${messages.length}');

    return TextCommandResult(buffer.toString());
  }
}
