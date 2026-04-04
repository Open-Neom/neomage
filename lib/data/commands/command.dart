// Command system — port of neom_claw/src/commands.ts + src/types/command.ts.
// Three command types: prompt (LLM-executed), local (sync), local-ui (Flutter).

import '../../domain/models/message.dart';
import '../tools/tool.dart';

/// Command execution type.
enum CommandType {
  /// Prompt sent to the LLM for processing.
  prompt,

  /// Local command returning text synchronously.
  local,

  /// Local command that renders Flutter UI.
  localUi,
}

/// Where a command was loaded from.
enum CommandSource {
  builtin,
  skills,
  plugin,
  managed,
  bundled,
  mcp,
}

/// Result of a local command execution.
sealed class CommandResult {
  const CommandResult();
}

class TextCommandResult extends CommandResult {
  final String value;
  const TextCommandResult(this.value);
}

class CompactCommandResult extends CommandResult {
  final List<Message> compactedMessages;
  final String? displayText;
  const CompactCommandResult(this.compactedMessages, {this.displayText});
}

class SkipCommandResult extends CommandResult {
  const SkipCommandResult();
}

/// Abstract base for all commands.
abstract class Command {
  /// Command name (without the `/` prefix).
  String get name;

  /// User-visible description.
  String get description;

  /// Execution type.
  CommandType get type;

  /// Alternative names for the command.
  List<String> get aliases => const [];

  /// Hint text for arguments.
  String? get argumentHint => null;

  /// Whether this command is enabled (feature flags, etc).
  bool get isEnabled => true;

  /// Whether this command is hidden from help/typeahead.
  bool get isHidden => false;

  /// Where this command was loaded from.
  CommandSource get source => CommandSource.builtin;

  /// Human-facing display name.
  String get displayName => name;

  /// When to use this command (for skills discovery).
  String? get whenToUse => null;

  /// Whether to execute immediately without waiting for stop point.
  bool get immediate => false;
}

/// A command that sends a prompt to the LLM.
abstract class PromptCommand extends Command {
  @override
  CommandType get type => CommandType.prompt;

  /// Progress message shown during execution.
  String get progressMessage;

  /// Tools the model is allowed to use.
  Set<String>? get allowedTools => null;

  /// Model override for this command.
  String? get model => null;

  /// Build the prompt content for this command.
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  );
}

/// A command that executes locally and returns a result.
abstract class LocalCommand extends Command {
  @override
  CommandType get type => CommandType.local;

  /// Whether this command can run in non-interactive mode.
  bool get supportsNonInteractive => false;

  /// Execute the command.
  Future<CommandResult> execute(String args, ToolUseContext context);
}

/// A command that renders Flutter UI (equivalent to local-jsx).
abstract class LocalUiCommand extends Command {
  @override
  CommandType get type => CommandType.localUi;

  /// Execute and return result via callback.
  Future<CommandResult> execute(
    String args,
    ToolUseContext context,
  );
}
