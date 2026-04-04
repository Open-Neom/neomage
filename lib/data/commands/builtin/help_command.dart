// /help command — shows available commands.

import '../../tools/tool.dart';
import '../command.dart';
import '../command_registry.dart';

class HelpCommand extends LocalCommand {
  final CommandRegistry registry;

  HelpCommand({required this.registry});

  @override
  String get name => 'help';

  @override
  String get description => 'Show available commands and usage';

  @override
  List<String> get aliases => const ['?', 'commands'];

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    if (args.isNotEmpty) {
      // Help for a specific command
      final cmd = registry.get(args.trim());
      if (cmd == null) {
        return TextCommandResult('Unknown command: /$args');
      }
      return TextCommandResult(
        '/${cmd.name} — ${cmd.command.description}'
        '${cmd.allAliases.isNotEmpty ? '\n  Aliases: ${cmd.allAliases.map((a) => "/$a").join(", ")}' : ''}'
        '${cmd.command.argumentHint != null ? '\n  Usage: /${cmd.name} ${cmd.command.argumentHint}' : ''}',
      );
    }

    // List all visible commands
    final commands = registry.visible;
    commands.sort((a, b) => a.name.compareTo(b.name));

    final buffer = StringBuffer();
    buffer.writeln('Available commands:');
    buffer.writeln();

    for (final cmd in commands) {
      final hint = cmd.command.argumentHint != null ? ' ${cmd.command.argumentHint}' : '';
      buffer.writeln('  /${cmd.name}$hint — ${cmd.command.description}');
    }

    buffer.writeln();
    buffer.writeln('Type /help <command> for more info on a specific command.');
    return TextCommandResult(buffer.toString());
  }
}
