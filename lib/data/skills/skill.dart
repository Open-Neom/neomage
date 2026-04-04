// Skills system — port of neom_claw/src/skills.
// User-defined prompt-based commands loaded from SKILL.md files.

import 'package:flutter_claw/core/platform/claw_io.dart';

import '../../domain/models/message.dart';
import '../commands/command.dart';
import '../tools/tool.dart';

/// A loaded skill definition.
class SkillDefinition {
  final String name;
  final String description;
  final String? whenToUse;
  final String promptContent;
  final Set<String>? allowedTools;
  final String? model;
  final String? argumentHint;
  final List<String>? argNames;
  final bool userInvocable;
  final bool disableModelInvocation;
  final String? context; // 'inline' or 'fork'
  final String? agent;
  final String filePath;
  final SkillSource source;

  const SkillDefinition({
    required this.name,
    required this.description,
    required this.promptContent,
    required this.filePath,
    this.whenToUse,
    this.allowedTools,
    this.model,
    this.argumentHint,
    this.argNames,
    this.userInvocable = true,
    this.disableModelInvocation = false,
    this.context,
    this.agent,
    this.source = SkillSource.user,
  });
}

/// Where a skill was loaded from.
enum SkillSource {
  user,
  project,
  plugin,
  bundled,
  mcp,
}

/// Skill as a PromptCommand (for registration in CommandRegistry).
class SkillCommand extends PromptCommand {
  final SkillDefinition skill;

  SkillCommand({required this.skill});

  @override
  String get name => skill.name;

  @override
  String get description => skill.description;

  @override
  String get progressMessage => 'running ${skill.name}';

  @override
  String? get argumentHint => skill.argumentHint;

  @override
  String? get whenToUse => skill.whenToUse;

  @override
  Set<String>? get allowedTools => skill.allowedTools;

  @override
  String? get model => skill.model;

  @override
  CommandSource get source => switch (skill.source) {
        SkillSource.user => CommandSource.skills,
        SkillSource.project => CommandSource.skills,
        SkillSource.plugin => CommandSource.plugin,
        SkillSource.bundled => CommandSource.bundled,
        SkillSource.mcp => CommandSource.mcp,
      };

  @override
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  ) async {
    var prompt = skill.promptContent;

    // Substitute $ARGUMENTS placeholder
    if (args.isNotEmpty) {
      prompt = prompt.replaceAll(r'$ARGUMENTS', args);
    }

    // Substitute named arguments
    if (skill.argNames != null && args.isNotEmpty) {
      final parts = args.split(RegExp(r'\s+'));
      for (var i = 0; i < skill.argNames!.length && i < parts.length; i++) {
        prompt = prompt.replaceAll('\$${skill.argNames![i]}', parts[i]);
      }
    }

    return [TextBlock(prompt)];
  }
}

/// Load skills from a directory.
/// Recursively finds SKILL.md files and parses their frontmatter.
Future<List<SkillDefinition>> loadSkillsFromDir(
  String dirPath, {
  SkillSource source = SkillSource.user,
}) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return const [];

  final skills = <SkillDefinition>[];

  await for (final entity in dir.list(recursive: true)) {
    if (entity is! File) continue;
    final filename = entity.path.split('/').last;
    if (filename != 'SKILL.md') continue;

    try {
      final content = await entity.readAsString();
      final skill = _parseSkillFile(content, entity.path, source);
      if (skill != null) skills.add(skill);
    } catch (_) {
      // Skip unreadable files
    }
  }

  return skills;
}

SkillDefinition? _parseSkillFile(
  String content,
  String filePath,
  SkillSource source,
) {
  // Parse frontmatter
  if (!content.startsWith('---')) {
    // No frontmatter — use first line as description
    final lines = content.split('\n');
    final firstLine = lines.firstWhere(
      (l) => l.trim().isNotEmpty,
      orElse: () => '',
    );
    final dirName = filePath.split('/').reversed.skip(1).first;

    return SkillDefinition(
      name: dirName,
      description: firstLine.replaceAll(RegExp(r'^#+\s*'), ''),
      promptContent: content,
      filePath: filePath,
      source: source,
    );
  }

  final endIndex = content.indexOf('---', 3);
  if (endIndex == -1) return null;

  final frontmatter = content.substring(3, endIndex).trim();
  final body = content.substring(endIndex + 3).trim();

  String? name;
  String? description;
  String? whenToUse;
  String? argumentHint;
  String? model;
  String? context;
  String? agent;
  Set<String>? allowedTools;
  List<String>? argNames;
  bool userInvocable = true;
  bool disableModelInvocation = false;

  for (final line in frontmatter.split('\n')) {
    final colonIdx = line.indexOf(':');
    if (colonIdx == -1) continue;

    final key = line.substring(0, colonIdx).trim();
    final value = line.substring(colonIdx + 1).trim();

    switch (key) {
      case 'name':
        name = value;
      case 'description':
        description = value;
      case 'when-to-use':
        whenToUse = value;
      case 'argument-hint':
        argumentHint = value;
      case 'model':
        model = value;
      case 'context':
        context = value;
      case 'agent':
        agent = value;
      case 'user-invocable':
        userInvocable = value.toLowerCase() == 'true';
      case 'disable-model-invocation':
        disableModelInvocation = value.toLowerCase() == 'true';
      case 'allowed-tools':
        allowedTools = _parseList(value).toSet();
      case 'arguments':
        argNames = _parseList(value);
    }
  }

  // Default name from directory
  name ??= filePath.split('/').reversed.skip(1).first;
  description ??= body.split('\n').firstWhere(
        (l) => l.trim().isNotEmpty,
        orElse: () => name!,
      );

  return SkillDefinition(
    name: name,
    description: description.replaceAll(RegExp(r'^#+\s*'), ''),
    promptContent: body,
    filePath: filePath,
    whenToUse: whenToUse,
    allowedTools: allowedTools,
    model: model,
    argumentHint: argumentHint,
    argNames: argNames,
    userInvocable: userInvocable,
    disableModelInvocation: disableModelInvocation,
    context: context,
    agent: agent,
    source: source,
  );
}

List<String> _parseList(String value) {
  // Handle YAML-like list: [a, b, c] or a, b, c
  return value
      .replaceAll('[', '')
      .replaceAll(']', '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
