// /diff command — prompt-based diff review.

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

class DiffCommand extends PromptCommand {
  @override
  String get name => 'diff';

  @override
  String get description => 'Show and explain current git changes';

  @override
  String get progressMessage => 'analyzing diff';

  @override
  Set<String> get allowedTools => const {'Bash', 'Read'};

  @override
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  ) async {
    final target = args.trim();
    final diffCmd = target.isNotEmpty ? 'git diff $target' : 'git diff';

    return [
      TextBlock(
        'Show the current git changes and provide a concise explanation.\n\n'
        '1. Run `$diffCmd`\n'
        '2. If no output, try `git diff --staged`\n'
        '3. Summarize the changes in a clear, structured way\n',
      ),
    ];
  }
}
