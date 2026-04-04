// /context command — show context window usage.

import '../../../domain/models/message.dart';
import '../../compact/compaction_service.dart';
import '../../tools/tool.dart';
import '../command.dart';

class ContextCommand extends LocalCommand {
  final CompactionService compactionService;
  final List<Message> Function() getMessages;
  final int contextWindow;

  ContextCommand({
    required this.compactionService,
    required this.getMessages,
    this.contextWindow = 200000,
  });

  @override
  String get name => 'context';

  @override
  String get description => 'Show context window usage and token estimates';

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final messages = getMessages();
    final estimated = compactionService.estimateTokenCount(messages);
    final percent = (estimated / contextWindow * 100).toStringAsFixed(1);

    final buffer = StringBuffer();
    buffer.writeln('Context Window Usage:');
    buffer.writeln('  Messages: ${messages.length}');
    buffer.writeln(
      '  Estimated tokens: ~$estimated / $contextWindow ($percent%)',
    );
    buffer.writeln('  Auto-compact threshold: ${contextWindow - 13000}');

    if (estimated > contextWindow * 0.8) {
      buffer.writeln(
        '  Warning: Approaching context limit. Consider /compact.',
      );
    }

    return TextCommandResult(buffer.toString());
  }
}
