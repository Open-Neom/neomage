// /session command — manage conversation sessions.

import '../../session/session_history.dart';
import '../../tools/tool.dart';
import '../command.dart';

class SessionCommand extends LocalCommand {
  final SessionHistoryManager historyManager;
  final String Function() getCurrentSessionId;

  SessionCommand({
    required this.historyManager,
    required this.getCurrentSessionId,
  });

  @override
  String get name => 'session';

  @override
  String get description => 'View and manage conversation sessions';

  @override
  String? get argumentHint => '[list|resume <id>|delete <id>]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
      case '':
        return _list();
      case 'current':
        return TextCommandResult('Current session: ${getCurrentSessionId()}');
      case 'delete':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /session delete <id>');
        }
        return _delete(parts[1]);
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /session [list|current|delete <id>]',
        );
    }
  }

  Future<CommandResult> _list() async {
    final sessions = await historyManager.listSessions();
    if (sessions.isEmpty) {
      return const TextCommandResult('No saved sessions.');
    }

    final current = getCurrentSessionId();
    final buffer = StringBuffer();
    buffer.writeln('Sessions (${sessions.length}):');
    for (final id in sessions.take(20)) {
      final marker = id == current ? ' (current)' : '';
      buffer.writeln('  $id$marker');
    }
    if (sessions.length > 20) {
      buffer.writeln('  ... and ${sessions.length - 20} more');
    }
    return TextCommandResult(buffer.toString());
  }

  Future<CommandResult> _delete(String sessionId) async {
    if (sessionId == getCurrentSessionId()) {
      return const TextCommandResult('Cannot delete the current session.');
    }
    final deleted = await historyManager.deleteSession(sessionId);
    if (!deleted) {
      return TextCommandResult('Session not found: $sessionId');
    }
    return TextCommandResult('Deleted session: $sessionId');
  }
}
