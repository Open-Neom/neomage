// /review command — prompt-based code review.

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

class ReviewCommand extends PromptCommand {
  @override
  String get name => 'review';

  @override
  String get description => 'Review code changes or a pull request';

  @override
  String? get argumentHint => '[PR number or file path]';

  @override
  String get progressMessage => 'reviewing code';

  @override
  Set<String> get allowedTools =>
      const {'Bash', 'Read', 'Glob', 'Grep'};

  @override
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  ) async {
    final target = args.trim();

    if (target.isEmpty) {
      return [
        const TextBlock(
          'Review the current git diff. Steps:\n\n'
          '1. Run `git diff` to see all changes\n'
          '2. If no diff, try `git diff --staged`\n'
          '3. Review each changed file for:\n'
          '   - Correctness and logic errors\n'
          '   - Security vulnerabilities (OWASP top 10)\n'
          '   - Performance issues\n'
          '   - Code style and best practices\n'
          '   - Missing error handling\n'
          '   - Test coverage gaps\n'
          '4. Provide a summary with:\n'
          '   - Overall assessment (approve/request changes)\n'
          '   - Specific issues found (file:line format)\n'
          '   - Suggestions for improvement\n',
        ),
      ];
    }

    // Check if it's a PR number
    if (RegExp(r'^\d+$').hasMatch(target)) {
      return [
        TextBlock(
          'Review pull request #$target. Steps:\n\n'
          '1. Run `gh pr view $target` to see PR details\n'
          '2. Run `gh pr diff $target` to see the changes\n'
          '3. Review each changed file for correctness, security, '
          'performance, and style\n'
          '4. Check PR comments with `gh api repos/{owner}/{repo}/pulls/$target/comments`\n'
          '5. Provide a structured review with specific line references\n',
        ),
      ];
    }

    // Assume file path
    return [
      TextBlock(
        'Review the file at `$target`. Steps:\n\n'
        '1. Read the file\n'
        '2. Analyze for correctness, security, performance, and style\n'
        '3. Provide specific feedback with line references\n',
      ),
    ];
  }
}
