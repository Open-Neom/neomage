// /memory command — manage persistent memory.

import '../../memdir/memdir_service.dart';
import '../../tools/tool.dart';
import '../command.dart';

class MemoryCommand extends LocalCommand {
  final MemdirService memdir;

  MemoryCommand({required this.memdir});

  @override
  String get name => 'memory';

  @override
  String get description => 'View and manage persistent memory files';

  @override
  String? get argumentHint => '[list|show <file>|delete <file>]';

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final parts = args.trim().split(RegExp(r'\s+'));
    final subcommand = parts.isNotEmpty ? parts[0] : 'list';

    switch (subcommand) {
      case 'list':
      case '':
        return _list();
      case 'show':
      case 'read':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /memory show <filename>');
        }
        return _show(parts[1]);
      case 'delete':
      case 'rm':
        if (parts.length < 2) {
          return const TextCommandResult('Usage: /memory delete <filename>');
        }
        return _delete(parts[1]);
      default:
        return TextCommandResult(
          'Unknown subcommand: $subcommand\n'
          'Usage: /memory [list|show <file>|delete <file>]',
        );
    }
  }

  Future<CommandResult> _list() async {
    final headers = await memdir.scanMemories();
    if (headers.isEmpty) {
      return const TextCommandResult('No memory files found.');
    }

    final buffer = StringBuffer();
    buffer.writeln('Memory files (${headers.length}):');
    buffer.writeln();

    for (final h in headers) {
      final type = h.type != null ? '[${h.type!.name}]' : '[?]';
      final desc = h.description ?? '(no description)';
      buffer.writeln('  $type ${h.filename} — $desc');
    }

    return TextCommandResult(buffer.toString());
  }

  Future<CommandResult> _show(String filename) async {
    final content = await memdir.readMemoryFile(
      '${memdir.projectRoot ?? "."}/$filename',
    );
    if (content == null) {
      return TextCommandResult('Memory file not found: $filename');
    }
    return TextCommandResult(content);
  }

  Future<CommandResult> _delete(String filename) async {
    final deleted = await memdir.deleteMemoryFile(filename);
    if (!deleted) {
      return TextCommandResult('Memory file not found: $filename');
    }
    return TextCommandResult('Deleted: $filename');
  }
}
