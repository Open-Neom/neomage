// /session command — manage conversation sessions.

import '../../session/session_history.dart';
import '../../tools/tool.dart';
import '../command.dart';

class SessionCommand extends LocalCommand {
  final SessionHistoryManager historyManager;
  final String Function() getCurrentSessionId;
  final Future<bool> Function(String sessionId)? onSessionResume;

  SessionCommand({
    required this.historyManager,
    required this.getCurrentSessionId,
    this.onSessionResume,
  });

  @override
  String get name => 'session';

  @override
  String get description => 'View and manage conversation sessions';

  @override
  List<String> get aliases => const ['sesiones', 'historial', 'platicas'];

  @override
  String? get argumentHint => '[list|current|resume <id>|delete <id>]';

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
      case 'resume':
      case 'load':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /session resume <id>');
        }
        if (onSessionResume == null) {
          return const TextCommandResult(
            'Session resume is not supported in this context.',
          );
        }
        final id = parts[1];
        final success = await onSessionResume!(id);
        if (!success) {
          return TextCommandResult('Session not found: $id');
        }
        return TextCommandResult('Resumed session: $id');
      case 'delete':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /session delete <id>');
        }
        return _delete(parts[1]);
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /session [list|current|resume <id>|delete <id>]',
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
