// /commit command — prompt-based git commit creation.

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

class CommitCommand extends PromptCommand {
  @override
  String get name => 'commit';

  @override
  String get description => 'Create a git commit with an AI-generated message';

  @override
  String get progressMessage => 'creating commit';

  @override
  Set<String> get allowedTools => const {'Bash', 'Read', 'Glob', 'Grep'};

  @override
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  ) async {
    final extraInstructions = args.isNotEmpty
        ? '\nAdditional instructions: $args'
        : '';

    return [
      TextBlock(
        'Create a git commit for the current changes. Follow these steps:\n\n'
        '1. Run `git status` to see all changes\n'
        '2. Run `git diff --staged` to see staged changes\n'
        '3. If nothing is staged, run `git diff` to see unstaged changes\n'
        '4. Run `git log --oneline -5` to see recent commit message style\n'
        '5. Draft a concise commit message that:\n'
        '   - Summarizes the nature of the changes\n'
        '   - Focuses on the "why" rather than the "what"\n'
        '   - Follows the existing commit message style\n'
        '6. Stage relevant files (prefer specific files over `git add .`)\n'
        '7. Create the commit\n'
        '8. Show the result with `git log -1`\n'
        '$extraInstructions',
      ),
    ];
  }
}
