// Command and skill types — ported from OpenClaude src/types/command.ts.

/// Command result display mode.
enum CommandResultDisplay { skip, system, user }

/// Result of executing a local command.
sealed class LocalCommandResult {
  const LocalCommandResult();
}

class TextCommandResult extends LocalCommandResult {
  final String text;
  final CommandResultDisplay display;
  const TextCommandResult(this.text, {this.display = CommandResultDisplay.user});
}

class CompactCommandResult extends LocalCommandResult {
  final String summary;
  const CompactCommandResult(this.summary);
}

class SkipCommandResult extends LocalCommandResult {
  const SkipCommandResult();
}

/// Source of a resume entrypoint.
enum ResumeSource {
  cliFlag,
  slashCommandPicker,
  slashCommandDirect,
  autoResume,
}

/// Resume entrypoint — how a session was resumed.
class ResumeEntrypoint {
  final ResumeSource source;
  final String? sessionId;

  const ResumeEntrypoint({required this.source, this.sessionId});
}

/// Command availability context.
enum CommandAvailability { claudeAi, console, both }

/// Base command definition with metadata.
class CommandBase {
  final String name;
  final String description;
  final List<String> aliases;
  final bool hidden;
  final bool enabled;
  final CommandAvailability availability;
  final bool requiresMcp;
  final String? version;
  final bool sensitive;

  const CommandBase({
    required this.name,
    required this.description,
    this.aliases = const [],
    this.hidden = false,
    this.enabled = true,
    this.availability = CommandAvailability.both,
    this.requiresMcp = false,
    this.version,
    this.sensitive = false,
  });
}

/// Command type discriminator.
enum CommandType { prompt, local, localJsx }

/// A prompt-based command configuration.
class PromptCommand {
  final String content;
  final int? maxContentLength;
  final List<String>? allowedTools;
  final String? model;
  final String? source;
  final String? pluginName;
  final bool fork;

  const PromptCommand({
    required this.content,
    this.maxContentLength,
    this.allowedTools,
    this.model,
    this.source,
    this.pluginName,
    this.fork = false,
  });
}

/// Full command definition — base + implementation.
class Command {
  final CommandBase base;
  final CommandType type;
  final PromptCommand? promptCommand;

  const Command({
    required this.base,
    required this.type,
    this.promptCommand,
  });

  String get name => base.name;
  String get description => base.description;
  bool get isEnabled => base.enabled;
}
