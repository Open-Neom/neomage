// System prompt builder — port of neom_claw system prompt construction.
// Assembles the system prompt from multiple sources.

import '../platform/platform_bridge.dart';

/// System prompt section.
class PromptSection {
  final String name;
  final String content;
  final int priority; // Lower = higher priority
  final bool isConditional;

  const PromptSection({
    required this.name,
    required this.content,
    this.priority = 50,
    this.isConditional = false,
  });
}

/// System prompt builder — assembles the full system prompt.
class SystemPromptBuilder {
  final List<PromptSection> _sections = [];
  final String _model;
  final PlatformBridge _platform;
  final DateTime _now;

  SystemPromptBuilder({
    required String model,
    required PlatformBridge platform,
    DateTime? now,
  })  : _model = model,
        _platform = platform,
        _now = now ?? DateTime.now();

  /// Add a section.
  void addSection(PromptSection section) {
    _sections.add(section);
  }

  /// Add the identity section.
  void addIdentity({String? customName}) {
    addSection(PromptSection(
      name: 'identity',
      content: '''
You are ${customName ?? 'Claw'}, an AI coding assistant powered by $_model.
You are pair programming with the user on their codebase.
Today's date is ${_formatDate(_now)}.''',
      priority: 0,
    ));
  }

  /// Add environment context.
  void addEnvironment({
    required String workingDir,
    String? shell,
    String? gitBranch,
  }) {
    final parts = [
      'Working directory: $workingDir',
      'Platform: ${_platform.platform.name}',
      if (shell != null) 'Shell: $shell',
      if (gitBranch != null) 'Git branch: $gitBranch',
    ];

    addSection(PromptSection(
      name: 'environment',
      content: parts.join('\n'),
      priority: 5,
    ));
  }

  /// Add tool descriptions.
  void addTools(List<({String name, String description})> tools) {
    if (tools.isEmpty) return;

    final buf = StringBuffer('Available tools:\n');
    for (final tool in tools) {
      buf.writeln('- ${tool.name}: ${tool.description}');
    }

    addSection(PromptSection(
      name: 'tools',
      content: buf.toString(),
      priority: 10,
    ));
  }

  /// Add user instructions (.neomclaw/INSTRUCTIONS.md content).
  void addUserInstructions(String instructions) {
    if (instructions.trim().isEmpty) return;

    addSection(PromptSection(
      name: 'user_instructions',
      content: '''
# User Instructions
The user has provided the following project-specific instructions:

$instructions''',
      priority: 20,
    ));
  }

  /// Add memory context.
  void addMemory(String memoryPrompt) {
    if (memoryPrompt.trim().isEmpty) return;

    addSection(PromptSection(
      name: 'memory',
      content: memoryPrompt,
      priority: 25,
    ));
  }

  /// Add coding conventions.
  void addConventions({
    String? language,
    String? framework,
    List<String> rules = const [],
  }) {
    if (language == null && framework == null && rules.isEmpty) return;

    final parts = <String>[];
    if (language != null) parts.add('Primary language: $language');
    if (framework != null) parts.add('Framework: $framework');
    for (final rule in rules) {
      parts.add('- $rule');
    }

    addSection(PromptSection(
      name: 'conventions',
      content: '# Coding Conventions\n${parts.join('\n')}',
      priority: 30,
    ));
  }

  /// Add safety guidelines.
  void addSafetyGuidelines() {
    addSection(PromptSection(
      name: 'safety',
      content: '''
# Safety Guidelines
- NEVER execute destructive operations without explicit user confirmation
- NEVER commit, push, or modify git history unless specifically asked
- NEVER expose secrets, API keys, or credentials in outputs
- ALWAYS respect file permission boundaries
- ALWAYS verify paths before file operations
- When uncertain, ask the user rather than assuming''',
      priority: 40,
    ));
  }

  /// Add plan mode instructions.
  void addPlanMode() {
    addSection(PromptSection(
      name: 'plan_mode',
      content: '''
# Plan Mode (Active)
You are in plan mode. You MUST NOT make any changes to the codebase.
Instead, analyze the task and propose a detailed implementation plan.
Use clear numbered steps and identify potential risks or tradeoffs.
When the user confirms, exit plan mode to begin implementation.''',
      priority: 1,
      isConditional: true,
    ));
  }

  /// Add compact mode context.
  void addCompactContext(String summary) {
    addSection(PromptSection(
      name: 'compact_context',
      content: '''
# Compacted Context
This conversation has been compacted. Here is the summary of prior context:

$summary''',
      priority: 3,
    ));
  }

  /// Add MCP server context.
  void addMcpServers(List<({String name, List<String> tools})> servers) {
    if (servers.isEmpty) return;

    final buf = StringBuffer('# MCP Servers\n');
    for (final server in servers) {
      buf.writeln('## ${server.name}');
      buf.writeln('Tools: ${server.tools.join(', ')}');
    }

    addSection(PromptSection(
      name: 'mcp',
      content: buf.toString(),
      priority: 15,
    ));
  }

  /// Add skill definitions.
  void addSkills(List<({String name, String description})> skills) {
    if (skills.isEmpty) return;

    final buf = StringBuffer('# Available Skills\n');
    for (final skill in skills) {
      buf.writeln('- /${skill.name}: ${skill.description}');
    }

    addSection(PromptSection(
      name: 'skills',
      content: buf.toString(),
      priority: 18,
    ));
  }

  /// Build the final system prompt.
  String build({int? maxTokens}) {
    final sorted = List.of(_sections)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    final buf = StringBuffer();
    for (final section in sorted) {
      if (buf.isNotEmpty) buf.write('\n\n');
      buf.write(section.content);
    }

    var result = buf.toString();

    // Truncate if needed (rough token estimate: 1 token ≈ 4 chars)
    if (maxTokens != null) {
      final maxChars = maxTokens * 4;
      if (result.length > maxChars) {
        result = result.substring(0, maxChars);
        result += '\n\n[System prompt truncated due to length]';
      }
    }

    return result;
  }

  /// Estimated token count of the built prompt.
  int get estimatedTokens {
    var chars = 0;
    for (final section in _sections) {
      chars += section.content.length;
    }
    return (chars / 4).ceil();
  }

  /// Clear all sections.
  void clear() => _sections.clear();

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
