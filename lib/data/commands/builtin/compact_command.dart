// /compact command — triggers conversation compaction.

import '../../../domain/models/message.dart';
import '../../compact/compaction_service.dart';
import '../../tools/tool.dart';
import '../command.dart';

class CompactCommand extends LocalCommand {
  final CompactionService compactionService;
  final List<Message> Function() getMessages;
  final String Function() getSystemPrompt;

  CompactCommand({
    required this.compactionService,
    required this.getMessages,
    required this.getSystemPrompt,
  });

  @override
  String get name => 'compact';

  @override
  String get description =>
      'Clear conversation history but keep a summary of prior context';

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final messages = getMessages();
    if (messages.isEmpty) {
      return const TextCommandResult('Nothing to compact.');
    }

    try {
      final result = await compactionService.compactConversation(
        messages: messages,
        systemPrompt: getSystemPrompt(),
      );

      final saved = result.preCompactTokenCount - result.postCompactTokenCount;
      return CompactCommandResult(
        result.compactedMessages,
        displayText:
            'Conversation compacted. '
            'Reduced from ~${result.preCompactTokenCount} to '
            '~${result.postCompactTokenCount} tokens '
            '(saved ~$saved tokens).',
      );
    } catch (e) {
      return TextCommandResult('Compaction failed: $e');
    }
  }
}
